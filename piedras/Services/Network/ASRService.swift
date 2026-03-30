import Foundation

private struct ProxyASRMessage: Decodable {
    let type: String
    let text: String?
    let startTimeMs: Double?
    let endTimeMs: Double?
    let message: String?
    let revision: Int?
    let fullText: String?
    let audioEndTimeMs: Double?
    let utterances: [ProxyASRUtterance]?
}

private struct ProxyASRUtterance: Decodable {
    let text: String
    let startTimeMs: Double
    let endTimeMs: Double
    let definite: Bool
}

struct ASRFinalResult {
    let text: String
    let startTime: Double
    let endTime: Double
}

enum ASRServiceError: LocalizedError {
    case handshakeTimedOut
    case connectionValidationFailed(String)
    case bufferedAudioOverflow
    case inactivityTimeout
    case connectionClosed
    case serviceError(String)

    var errorDescription: String? {
        switch self {
        case .handshakeTimedOut:
            return "实时转写握手超时，录音仍在继续，停止后将自动补转写。"
        case let .connectionValidationFailed(detail):
            return "实时转写连接校验失败：\(detail)"
        case .bufferedAudioOverflow:
            return "实时转写暂时中断，录音仍在继续，停止后将自动补转写。"
        case .inactivityTimeout:
            return "实时转写连接超时，录音仍在继续，停止后将自动补转写。"
        case .connectionClosed:
            return "实时转写连接已关闭，录音仍在继续，停止后将自动补转写。"
        case let .serviceError(message):
            return message
        }
    }
}

actor ASRReadyGate {
    private enum State {
        case idle
        case ready
        case failed(Error)
    }

    private var state: State = .idle

    func waitUntilReady(timeout: Duration) async throws {
        let deadline = ContinuousClock.now + timeout

        while true {
            switch state {
            case .ready:
                return
            case let .failed(error):
                throw error
            case .idle:
                if ContinuousClock.now >= deadline {
                    throw ASRServiceError.handshakeTimedOut
                }
                try await Task.sleep(for: .milliseconds(50))
            }
        }
    }

    func markReady() {
        state = .ready
    }

    func fail(_ error: Error) {
        state = .failed(error)
    }

    func reset() {
        state = .idle
    }
}

enum ASRBufferPolicy {
    static func shouldFailPendingBuffer(
        currentBufferedBytes: Int,
        incomingBytes: Int,
        maxBufferedBytes: Int
    ) -> Bool {
        currentBufferedBytes + incomingBytes > maxBufferedBytes
    }
}

@MainActor
protocol ASRServicing: AnyObject {
    var onPartialText: ((String) -> Void)? { get set }
    var onFinalResult: ((ASRFinalResult) -> Void)? { get set }
    var onRecognitionSnapshot: ((ASRRecognitionSnapshot) -> Void)? { get set }
    var onStateChange: ((ASRConnectionState) -> Void)? { get set }
    var onError: ((String) -> Void)? { get set }
    var onTransportEvent: ((String) -> Void)? { get set }
    var onPCMChunkSent: ((Int) -> Void)? { get set }

    func startStreaming(workspaceID: String?, meetingID: String?) async throws
    func enqueuePCM(_ data: Data)
    func stopStreaming() async
}

@MainActor
final class ASRService: ASRServicing {
    private static let handshakeTimeout: Duration = .seconds(3)
    private static let connectionValidationTimeout: Duration = .seconds(2)
    private static let inactivityTimeout: TimeInterval = 10
    private static let inactivityCheckInterval: Duration = .seconds(1)

    private let apiClient: APIClient
    private let session: URLSession

    private var webSocketTask: URLSessionWebSocketTask?
    private var receiveTask: Task<Void, Never>?
    private var inactivityWatchdogTask: Task<Void, Never>?
    private var packetByteSize = 6_400
    private var readyForAudio = false
    private var isStopping = false
    private var pendingPCMBuffer = Data()
    private var pendingPCMChunks: [Data] = []
    private var sendQueue: [Data] = []
    private var isDrainingSendQueue = false
    private var maxBufferedPCMBytes = 96_000
    private var lastTransportActivityAt: Date?
    private var transportActivityMonitoringEnabled = false
    private var hasReceivedSnapshot = false
    private let readyGate = ASRReadyGate()

    var onPartialText: ((String) -> Void)?
    var onFinalResult: ((ASRFinalResult) -> Void)?
    var onRecognitionSnapshot: ((ASRRecognitionSnapshot) -> Void)?
    var onStateChange: ((ASRConnectionState) -> Void)?
    var onError: ((String) -> Void)?
    var onTransportEvent: ((String) -> Void)?
    var onPCMChunkSent: ((Int) -> Void)?

    init(apiClient: APIClient, session: URLSession = .shared) {
        self.apiClient = apiClient
        self.session = session
    }

    func startStreaming(workspaceID: String?, meetingID: String?) async throws {
        await cleanupTransport(notifyDisconnected: false)
        await readyGate.reset()

        onPartialText?("")
        transition(to: .connecting)
        onTransportEvent?("正在请求 ASR 会话")

        let response = try await apiClient.createASRSession(
            sampleRate: Int(PCMConverter.targetSampleRate),
            channels: 1,
            workspaceID: workspaceID,
            meetingID: meetingID
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
        hasReceivedSnapshot = false
        packetByteSize = Self.makePacketByteSize(
            sampleRate: descriptor.sampleRate ?? Int(PCMConverter.targetSampleRate),
            channels: descriptor.channels ?? 1,
            packetDurationMs: descriptor.packetDurationMs ?? 200
        )
        let bytesPerSecond = max(descriptor.sampleRate ?? Int(PCMConverter.targetSampleRate), 8_000)
            * max(descriptor.channels ?? 1, 1)
            * 2
        maxBufferedPCMBytes = bytesPerSecond * 30

        let task = session.webSocketTask(with: url)
        webSocketTask = task
        task.resume()
        onTransportEvent?("WebSocket 已建立")

        receiveTask = Task { [weak self, task] in
            await self?.receiveLoop(task: task)
        }

        do {
            try await readyGate.waitUntilReady(timeout: Self.handshakeTimeout)
            try await validateConnection(task)
        } catch {
            let message = error.localizedDescription
            transition(to: .degraded)
            onTransportEvent?(message)
            await readyGate.fail(error)
            await cleanupTransport(notifyDisconnected: false)
            throw error
        }
    }

    func enqueuePCM(_ data: Data) {
        guard webSocketTask != nil, !isStopping, !data.isEmpty else {
            return
        }

        if !readyForAudio,
           ASRBufferPolicy.shouldFailPendingBuffer(
               currentBufferedBytes: totalBufferedPCMBytes,
               incomingBytes: data.count,
               maxBufferedBytes: maxBufferedPCMBytes
           ) {
            let message = ASRServiceError.bufferedAudioOverflow.localizedDescription
            transition(to: .degraded)
            onTransportEvent?(message)
            onError?(message)
            Task { @MainActor [weak self] in
                await self?.readyGate.fail(ASRServiceError.bufferedAudioOverflow)
                await self?.cleanupTransport(notifyDisconnected: false)
            }
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
                await readyGate.fail(error)
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
            noteTransportActivity(enableMonitoring: false)
            transition(to: .connected)
            onTransportEvent?("ASR 已就绪")
            Task { await readyGate.markReady() }
            flushPendingChunksIfReady()

        case "snapshot":
            noteTransportActivity()
            guard let revision = message.revision,
                  let audioEndTimeMs = message.audioEndTimeMs else {
                return
            }

            hasReceivedSnapshot = true
            let utterances = (message.utterances ?? []).map {
                ASRRecognitionUtterance(
                    text: $0.text,
                    startTimeMs: $0.startTimeMs,
                    endTimeMs: $0.endTimeMs,
                    definite: $0.definite
                )
            }
            onRecognitionSnapshot?(
                ASRRecognitionSnapshot(
                    revision: revision,
                    fullText: message.fullText ?? "",
                    audioEndTimeMs: audioEndTimeMs,
                    utterances: utterances
                )
            )

        case "partial":
            guard !hasReceivedSnapshot else { return }
            noteTransportActivity()
            onPartialText?(message.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "")

        case "final":
            guard !hasReceivedSnapshot else { return }
            noteTransportActivity()
            let result = message.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !result.isEmpty else { return }
            let startTime = message.startTimeMs ?? 0
            let endTime = max(message.endTimeMs ?? startTime, startTime)
            onPartialText?("")
            onTransportEvent?("收到句末结果")
            onFinalResult?(ASRFinalResult(text: result, startTime: startTime, endTime: endTime))

        case "error":
            noteTransportActivity()
            transition(to: .degraded)
            let detail = message.message ?? "实时转写服务异常。"
            onTransportEvent?(detail)
            onError?(detail)
            Task { @MainActor [weak self] in
                await self?.readyGate.fail(ASRServiceError.serviceError(detail))
                await self?.cleanupTransport(notifyDisconnected: false)
            }

        case "closed":
            noteTransportActivity()
            onTransportEvent?(isStopping ? "ASR 已关闭" : "ASR 连接关闭")
            transition(to: isStopping ? .disconnected : .degraded)
            if !isStopping {
                let error = ASRServiceError.connectionClosed
                onError?(error.localizedDescription)
                Task { @MainActor [weak self] in
                    await self?.readyGate.fail(error)
                    await self?.cleanupTransport(notifyDisconnected: false)
                }
            }

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
                    noteTransportActivity(enableMonitoring: true)
                    onPCMChunkSent?(payload.count)
                } catch {
                    guard !isStopping else { break }
                    await readyGate.fail(error)
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

    private var totalBufferedPCMBytes: Int {
        pendingPCMBuffer.count
            + pendingPCMChunks.reduce(0) { $0 + $1.count }
            + sendQueue.reduce(0) { $0 + $1.count }
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

    private func validateConnection(_ task: URLSessionWebSocketTask) async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                try await withCheckedThrowingContinuation { continuation in
                    task.sendPing { error in
                        if let error {
                            continuation.resume(throwing: error)
                        } else {
                            continuation.resume(returning: ())
                        }
                    }
                }
            }

            group.addTask {
                try await Task.sleep(for: Self.connectionValidationTimeout)
                throw ASRServiceError.connectionValidationFailed("WebSocket ping 超时。")
            }

            _ = try await group.next()
            group.cancelAll()
        }
    }

    private func noteTransportActivity(enableMonitoring: Bool? = nil) {
        if let enableMonitoring {
            transportActivityMonitoringEnabled = enableMonitoring || transportActivityMonitoringEnabled
        }

        lastTransportActivityAt = .now
        startInactivityWatchdogIfNeeded()
    }

    private func startInactivityWatchdogIfNeeded() {
        guard inactivityWatchdogTask == nil else { return }
        inactivityWatchdogTask = Task { @MainActor [weak self] in
            while let self, !Task.isCancelled {
                try? await Task.sleep(for: Self.inactivityCheckInterval)
                await self.handleInactivityWatchdogTick()
            }
        }
    }

    private func handleInactivityWatchdogTick() async {
        guard transportActivityMonitoringEnabled,
              readyForAudio,
              !isStopping,
              webSocketTask != nil,
              let lastTransportActivityAt else {
            return
        }

        guard Date().timeIntervalSince(lastTransportActivityAt) >= Self.inactivityTimeout else {
            return
        }

        let error = ASRServiceError.inactivityTimeout
        transition(to: .degraded)
        onTransportEvent?(error.localizedDescription)
        onError?(error.localizedDescription)
        await readyGate.fail(error)
        await cleanupTransport(notifyDisconnected: false)
    }

    private func transition(to state: ASRConnectionState) {
        onStateChange?(state)
    }

    private func cleanupTransport(notifyDisconnected: Bool) async {
        receiveTask?.cancel()
        receiveTask = nil
        inactivityWatchdogTask?.cancel()
        inactivityWatchdogTask = nil

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
        transportActivityMonitoringEnabled = false
        lastTransportActivityAt = nil
        hasReceivedSnapshot = false
        await readyGate.reset()

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
