import Foundation

private struct AliyunWSMessage: Decodable {
    struct Header: Decodable {
        let name: String?
        let status: Int?
        let statusText: String?

        private enum CodingKeys: String, CodingKey {
            case name
            case status
            case statusText = "status_text"
        }
    }

    struct Payload: Decodable {
        let result: String?
        let beginTime: Double?
        let endTime: Double?

        private enum CodingKeys: String, CodingKey {
            case result
            case beginTime = "begin_time"
            case endTime = "end_time"
        }
    }

    let header: Header?
    let payload: Payload?
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
    private var pendingPCM: [Data] = []
    private var sendQueue: [Data] = []
    private var isDrainingSendQueue = false
    private var hasStartedTranscription = false
    private var isStopping = false
    private var currentTaskID = ""
    private var currentAppKey = ""
    private var currentVocabularyID: String?
    private var sessionStartEpochMS: Double = 0

    var onPartialText: ((String) -> Void)?
    var onFinalResult: ((ASRFinalResult) -> Void)?
    var onStateChange: ((ASRConnectionState) -> Void)?
    var onError: ((String) -> Void)?

    init(apiClient: APIClient, session: URLSession = .shared) {
        self.apiClient = apiClient
        self.session = session
    }

    func startStreaming(workspaceID: String?) async throws {
        await cleanupTransport(notifyDisconnected: false)

        onPartialText?("")
        transition(to: .connecting)

        let response = try await apiClient.createASRSession(
            sampleRate: Int(PCMConverter.targetSampleRate),
            channels: 1,
            workspaceID: workspaceID
        )

        guard let descriptor = response.session else {
            throw APIClientError.requestFailed(response.error ?? "ASR 会话返回不完整。")
        }

        guard let encodedToken = descriptor.token.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "\(descriptor.wsUrl)?token=\(encodedToken)") else {
            throw APIClientError.invalidResponse
        }

        pendingPCM.removeAll()
        sendQueue.removeAll()
        isDrainingSendQueue = false
        hasStartedTranscription = false
        isStopping = false
        currentTaskID = Self.makeMessageID()
        currentAppKey = descriptor.appKey
        currentVocabularyID = descriptor.vocabularyId
        sessionStartEpochMS = Date().timeIntervalSince1970 * 1000

        let task = session.webSocketTask(with: url)
        webSocketTask = task
        task.resume()

        receiveTask = Task { [weak self, task] in
            await self?.receiveLoop(task: task)
        }

        try await sendStartMessage()
    }

    func enqueuePCM(_ data: Data) {
        guard webSocketTask != nil, !isStopping else {
            return
        }

        if hasStartedTranscription {
            sendQueue.append(data)
            drainSendQueueIfNeeded()
        } else {
            pendingPCM.append(data)
            if pendingPCM.count > 12 {
                pendingPCM.removeFirst(pendingPCM.count - 12)
            }
        }
    }

    func stopStreaming() async {
        guard webSocketTask != nil else {
            transition(to: .idle)
            onPartialText?("")
            return
        }

        isStopping = true

        if hasStartedTranscription {
            try? await sendStopMessage()
            try? await Task.sleep(for: .milliseconds(350))
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
              let message = try? JSONDecoder().decode(AliyunWSMessage.self, from: data) else {
            return
        }

        let eventName = message.header?.name
        let result = message.payload?.result?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        switch eventName {
        case "TranscriptionStarted":
            hasStartedTranscription = true
            transition(to: .connected)
            flushPendingPCM()

        case "TranscriptionResultChanged":
            onPartialText?(result)

        case "SentenceEnd":
            guard !result.isEmpty else { return }
            let beginTime = message.payload?.beginTime ?? 0
            let endTime = message.payload?.endTime ?? beginTime
            onPartialText?("")
            onFinalResult?(
                ASRFinalResult(
                    text: result,
                    startTime: sessionStartEpochMS + beginTime,
                    endTime: sessionStartEpochMS + max(endTime, beginTime)
                )
            )

        case "TaskFailed":
            let errorText = message.header?.statusText ?? "阿里云 ASR 任务失败。"
            transition(to: .degraded)
            onError?(errorText)
            pendingPCM.removeAll()
            sendQueue.removeAll()

        case "TranscriptionCompleted":
            transition(to: .disconnected)

        default:
            break
        }
    }

    private func flushPendingPCM() {
        guard !pendingPCM.isEmpty else { return }
        sendQueue.append(contentsOf: pendingPCM)
        pendingPCM.removeAll()
        drainSendQueueIfNeeded()
    }

    private func drainSendQueueIfNeeded() {
        guard !isDrainingSendQueue else { return }
        guard webSocketTask != nil else { return }

        isDrainingSendQueue = true
        Task { [weak self] in
            guard let self else { return }

            while let payload = nextPCMChunk() {
                guard let webSocketTask else { break }
                do {
                    try await webSocketTask.send(.data(payload))
                } catch {
                    guard !isStopping else { break }
                    transition(to: .degraded)
                    onError?(error.localizedDescription)
                    await cleanupTransport(notifyDisconnected: false)
                    break
                }
            }

            isDrainingSendQueue = false
        }
    }

    private func nextPCMChunk() -> Data? {
        guard !isStopping, !sendQueue.isEmpty else { return nil }
        return sendQueue.removeFirst()
    }

    private func sendStartMessage() async throws {
        var payloadBody: [String: Any] = [
            "format": "pcm",
            "sample_rate": Int(PCMConverter.targetSampleRate),
            "enable_intermediate_result": true,
            "enable_punctuation_prediction": true,
            "enable_inverse_text_normalization": true,
        ]

        if let currentVocabularyID {
            payloadBody["vocabulary_id"] = currentVocabularyID
        }

        let payload: [String: Any] = [
            "header": [
                "appkey": currentAppKey,
                "message_id": Self.makeMessageID(),
                "task_id": currentTaskID,
                "namespace": "SpeechTranscriber",
                "name": "StartTranscription",
            ],
            "payload": payloadBody,
        ]

        try await sendJSON(payload)
    }

    private func sendStopMessage() async throws {
        let payload: [String: Any] = [
            "header": [
                "appkey": currentAppKey,
                "message_id": Self.makeMessageID(),
                "task_id": currentTaskID,
                "namespace": "SpeechTranscriber",
                "name": "StopTranscription",
            ],
        ]

        try await sendJSON(payload)
    }

    private func sendJSON(_ payload: [String: Any]) async throws {
        guard let webSocketTask else {
            throw APIClientError.invalidResponse
        }

        let data = try JSONSerialization.data(withJSONObject: payload)
        guard let text = String(data: data, encoding: .utf8) else {
            throw APIClientError.invalidResponse
        }

        try await webSocketTask.send(.string(text))
    }

    private func cleanupTransport(notifyDisconnected: Bool) async {
        receiveTask?.cancel()
        receiveTask = nil

        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil

        pendingPCM.removeAll()
        sendQueue.removeAll()
        isDrainingSendQueue = false
        hasStartedTranscription = false
        isStopping = false
        currentTaskID = ""
        currentAppKey = ""
        currentVocabularyID = nil
        sessionStartEpochMS = 0

        onPartialText?("")

        if notifyDisconnected {
            transition(to: .disconnected)
        }
    }

    private func transition(to state: ASRConnectionState) {
        onStateChange?(state)
    }

    private static func makeMessageID() -> String {
        UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
    }
}
