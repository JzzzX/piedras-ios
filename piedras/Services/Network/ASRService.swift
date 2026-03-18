import Foundation

private struct ProxyASRMessage: Decodable {
    let type: String
    let text: String?
    let startTimeMs: Double?
    let endTimeMs: Double?
    let message: String?
}

struct ASRFinalResult {
    let text: String
    let startTime: Double
    let endTime: Double
}

@MainActor
final class ASRService {
    private let apiClient: APIClient
    private let session: URLSession

    private var webSocketTask: URLSessionWebSocketTask?
    private var receiveTask: Task<Void, Never>?
    private var packetByteSize = 6_400
    private var readyForAudio = false
    private var isStopping = false
    private var pendingPCMBuffer = Data()
    private var pendingPCMChunks: [Data] = []
    private var sendQueue: [Data] = []
    private var isDrainingSendQueue = false

    var onPartialText: ((String) -> Void)?
    var onFinalResult: ((ASRFinalResult) -> Void)?
    var onStateChange: ((ASRConnectionState) -> Void)?
    var onError: ((String) -> Void)?
    var onTransportEvent: ((String) -> Void)?
    var onPCMChunkSent: ((Int) -> Void)?

    init(apiClient: APIClient, session: URLSession = .shared) {
        self.apiClient = apiClient
        self.session = session
    }

    func startStreaming(workspaceID: String?) async throws {
        await cleanupTransport(notifyDisconnected: false)

        onPartialText?("")
        transition(to: .connecting)
        onTransportEvent?("正在请求 ASR 会话")

        let response = try await apiClient.createASRSession(
            sampleRate: Int(PCMConverter.targetSampleRate),
            channels: 1,
            workspaceID: workspaceID
        )

        guard let descriptor = response.session,
              let url = URL(string: descriptor.wsUrl) else {
            throw APIClientError.requestFailed(response.error ?? "ASR 会话返回不完整。")
        }

        readyForAudio = false
        isStopping = false
        pendingPCMBuffer.removeAll(keepingCapacity: false)
        pendingPCMChunks.removeAll(keepingCapacity: false)
        sendQueue.removeAll(keepingCapacity: false)
        isDrainingSendQueue = false
        packetByteSize = Self.makePacketByteSize(
            sampleRate: descriptor.sampleRate ?? Int(PCMConverter.targetSampleRate),
            channels: descriptor.channels ?? 1,
            packetDurationMs: descriptor.packetDurationMs ?? 200
        )

        let task = session.webSocketTask(with: url)
        webSocketTask = task
        task.resume()
        onTransportEvent?("WebSocket 已建立")

        receiveTask = Task { [weak self, task] in
            await self?.receiveLoop(task: task)
        }
    }

    func enqueuePCM(_ data: Data) {
        guard webSocketTask != nil, !isStopping, !data.isEmpty else {
            return
        }

        pendingPCMBuffer.append(data)
        flushBufferIntoChunks(includeRemainder: false)
    }

    func stopStreaming() async {
        guard webSocketTask != nil else {
            transition(to: .idle)
            onPartialText?("")
            return
        }

        isStopping = true
        flushBufferIntoChunks(includeRemainder: true)
        flushPendingChunksIfReady()

        if readyForAudio {
            drainSendQueueIfNeeded()
            try? await waitForQueueToDrain(timeoutMS: 800)
            try? await sendStopMessage()
            onTransportEvent?("已发送停止指令")
            try? await Task.sleep(for: .milliseconds(250))
        }

        await cleanupTransport(notifyDisconnected: true)
    }

    private func receiveLoop(task: URLSessionWebSocketTask) async {
        while !Task.isCancelled {
            do {
                let message = try await task.receive()
                switch message {
                case let .string(text):
                    handleTextMessage(text)
                case let .data(data):
                    if let text = String(data: data, encoding: .utf8) {
                        handleTextMessage(text)
                    }
                @unknown default:
                    break
                }
            } catch {
                guard !isStopping else { break }
                transition(to: .degraded)
                onError?(error.localizedDescription)
                await cleanupTransport(notifyDisconnected: false)
                break
            }
        }
    }

    private func handleTextMessage(_ text: String) {
        guard let data = text.data(using: .utf8),
              let message = try? JSONDecoder().decode(ProxyASRMessage.self, from: data) else {
            return
        }

        switch message.type {
        case "ready":
            readyForAudio = true
            transition(to: .connected)
            onTransportEvent?("ASR 已就绪")
            flushPendingChunksIfReady()

        case "partial":
            onPartialText?(message.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "")

        case "final":
            let result = message.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !result.isEmpty else { return }
            let startTime = message.startTimeMs ?? 0
            let endTime = max(message.endTimeMs ?? startTime, startTime)
            onPartialText?("")
            onTransportEvent?("收到句末结果")
            onFinalResult?(ASRFinalResult(text: result, startTime: startTime, endTime: endTime))

        case "error":
            transition(to: .degraded)
            onTransportEvent?(message.message ?? "实时转写服务异常")
            onError?(message.message ?? "实时转写服务异常。")

        case "closed":
            onTransportEvent?(isStopping ? "ASR 已关闭" : "ASR 连接关闭")
            transition(to: isStopping ? .disconnected : .degraded)

        default:
            break
        }
    }

    private func flushBufferIntoChunks(includeRemainder: Bool) {
        while pendingPCMBuffer.count >= packetByteSize {
            pendingPCMChunks.append(Data(pendingPCMBuffer.prefix(packetByteSize)))
            pendingPCMBuffer.removeFirst(packetByteSize)
        }

        if includeRemainder, !pendingPCMBuffer.isEmpty {
            pendingPCMChunks.append(pendingPCMBuffer)
            pendingPCMBuffer.removeAll(keepingCapacity: false)
        }

        flushPendingChunksIfReady()
    }

    private func flushPendingChunksIfReady() {
        guard readyForAudio else { return }
        guard !pendingPCMChunks.isEmpty else { return }
        sendQueue.append(contentsOf: pendingPCMChunks)
        pendingPCMChunks.removeAll(keepingCapacity: false)
        drainSendQueueIfNeeded()
    }

    private func drainSendQueueIfNeeded() {
        guard !isDrainingSendQueue else { return }
        guard webSocketTask != nil, readyForAudio else { return }

        isDrainingSendQueue = true
        Task { [weak self] in
            guard let self else { return }

            while let payload = nextPCMChunk() {
                guard let webSocketTask else { break }
                do {
                    try await webSocketTask.send(.data(payload))
                    onPCMChunkSent?(payload.count)
                } catch {
                    guard !isStopping else { break }
                    transition(to: .degraded)
                    onTransportEvent?(error.localizedDescription)
                    onError?(error.localizedDescription)
                    await cleanupTransport(notifyDisconnected: false)
                    break
                }
            }

            isDrainingSendQueue = false
        }
    }

    private func nextPCMChunk() -> Data? {
        guard readyForAudio, !sendQueue.isEmpty else { return nil }
        return sendQueue.removeFirst()
    }

    private func waitForQueueToDrain(timeoutMS: Int) async throws {
        let deadline = Date().addingTimeInterval(Double(timeoutMS) / 1000)
        while (!sendQueue.isEmpty || isDrainingSendQueue) && Date() < deadline {
            try await Task.sleep(for: .milliseconds(40))
        }
    }

    private func sendStopMessage() async throws {
        guard let webSocketTask else { return }
        try await webSocketTask.send(.string("{\"type\":\"stop\"}"))
    }

    private func transition(to state: ASRConnectionState) {
        onStateChange?(state)
    }

    private func cleanupTransport(notifyDisconnected: Bool) async {
        receiveTask?.cancel()
        receiveTask = nil

        if let webSocketTask {
            webSocketTask.cancel(with: .goingAway, reason: nil)
        }

        webSocketTask = nil
        readyForAudio = false
        isStopping = false
        pendingPCMBuffer.removeAll(keepingCapacity: false)
        pendingPCMChunks.removeAll(keepingCapacity: false)
        sendQueue.removeAll(keepingCapacity: false)
        isDrainingSendQueue = false

        onPartialText?("")
        onTransportEvent?(notifyDisconnected ? "ASR 已断开" : "等待连接")
        transition(to: notifyDisconnected ? .disconnected : .idle)
    }

    private static func makePacketByteSize(sampleRate: Int, channels: Int, packetDurationMs: Int) -> Int {
        let normalizedRate = max(sampleRate, 8_000)
        let normalizedChannels = max(channels, 1)
        let normalizedDuration = max(packetDurationMs, 50)
        let bytesPerSecond = normalizedRate * normalizedChannels * 2
        let computedSize = Int((Double(bytesPerSecond) * Double(normalizedDuration)) / 1000)
        return max(computedSize, 3_200)
    }
}
