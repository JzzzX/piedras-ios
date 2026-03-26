import Foundation
import SwiftData
import Testing
@testable import piedras

@MainActor
private final class MeetingTypeAutoRefreshMockURLProtocol: URLProtocol {
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    static func reset() {
        requestHandler = nil
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.requestHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

@MainActor
private final class NoopMeetingTypeAudioRecorderService: AudioRecorderServicing {
    var onProgress: ((Double, Int) -> Void)?
    var onPCMData: ((Data) -> Void)?
    var onCaptureStateChange: ((String) -> Void)?
    var onSourcePlaybackUpdate: ((TimeInterval, TimeInterval, Bool, String?) -> Void)?
    var onLifecycleEvent: ((AudioSessionLifecycleEvent) -> Void)?

    func startRecording(
        meetingID: String,
        sourceAudio: SourceAudioAsset?
    ) async throws -> RecordingStartArtifact {
        RecordingStartArtifact(
            fileURL: URL(fileURLWithPath: "/tmp/meeting-type-auto-refresh-start.m4a"),
            mimeType: "audio/m4a",
            inputMode: .microphone,
            sourceAudioLocalPath: nil,
            sourceAudioDisplayName: nil,
            sourceAudioDurationSeconds: 0
        )
    }

    func pauseRecording() throws {}
    func resumeRecording() throws {}

    func stopRecording() throws -> LocalAudioArtifact {
        LocalAudioArtifact(
            fileURL: URL(fileURLWithPath: "/tmp/meeting-type-auto-refresh-stop.m4a"),
            durationSeconds: 0,
            mimeType: "audio/m4a"
        )
    }

    func toggleSourceAudioPlayback() throws {}

    func reconcileForegroundRecording() -> AudioRecorderForegroundRecoveryResult {
        .healthy
    }

    func currentRecordingDurationSeconds() -> Int { 0 }
    func makeRecordingSnapshot() throws -> RecordingSnapshotArtifact? { nil }
}

@MainActor
private final class NoopMeetingTypeASRService: ASRServicing {
    var onPartialText: ((String) -> Void)?
    var onFinalResult: ((ASRFinalResult) -> Void)?
    var onStateChange: ((ASRConnectionState) -> Void)?
    var onError: ((String) -> Void)?
    var onTransportEvent: ((String) -> Void)?
    var onPCMChunkSent: ((Int) -> Void)?

    func startStreaming(workspaceID: String?) async throws {}
    func enqueuePCM(_ data: Data) {}
    func stopStreaming() async {}
}

@MainActor
private final class NoopMeetingTypeAudioFileTranscriptionService: AudioFileTranscriptionServicing {
    func transcribe(
        fileURL: URL,
        workspaceID: String?,
        onPhaseChange: @escaping @MainActor (AudioFileTranscriptionPhase) -> Void,
        onPartialText: @escaping @MainActor (String) -> Void,
        onFinalResult: @escaping @MainActor (ASRFinalResult) -> Void
    ) async throws {}
}

@MainActor
private final class NoopMeetingTypeRecordingLiveActivityCoordinator: RecordingLiveActivityCoordinating {
    func start(meetingID: String, phase: RecordingLiveActivityPhase, durationSeconds: Int) {}
    func update(phase: RecordingLiveActivityPhase, durationSeconds: Int) {}
    func end() {}
}

@MainActor
private final class StubMeetingTypeSyncService: MeetingSyncServicing {
    private(set) var syncedMeetingIDs: [String] = []

    func syncPendingMeetings() async -> MeetingSyncBatchResult {
        .init(syncedCount: 0, failedCount: 0)
    }

    func syncMeeting(id: String) async throws {
        syncedMeetingIDs.append(id)
    }

    func refreshRemoteMeetings() async throws -> Int { 0 }
}

@Suite(.serialized)
struct MeetingTypeAutoRefreshTests {
    @MainActor
    @Test
    func changingMeetingTypeWithExistingEnhancedNotesAutoRefreshesAIContent() async throws {
        MeetingTypeAutoRefreshMockURLProtocol.reset()
        defer { MeetingTypeAutoRefreshMockURLProtocol.reset() }

        let container = try ModelContainerFactory.makeContainer(inMemory: true)
        let repository = MeetingRepository(modelContext: container.mainContext)
        let chatRepository = ChatSessionRepository(modelContext: container.mainContext)
        let settingsStore = makeSettingsStore()
        settingsStore.hiddenWorkspaceID = "workspace-1"
        settingsStore.workspaceBootstrapState = .success
        settingsStore.markBackendReachable()
        let apiClient = makeAPIClient(settingsStore: settingsStore)
        let syncService = StubMeetingTypeSyncService()

        let store = MeetingStore(
            repository: repository,
            chatSessionRepository: chatRepository,
            settingsStore: settingsStore,
            recordingSessionStore: RecordingSessionStore(),
            appActivityCoordinator: AppActivityCoordinator(),
            recordingLiveActivityCoordinator: NoopMeetingTypeRecordingLiveActivityCoordinator(),
            audioRecorderService: NoopMeetingTypeAudioRecorderService(),
            audioFileTranscriptionService: NoopMeetingTypeAudioFileTranscriptionService(),
            apiClient: apiClient,
            asrService: NoopMeetingTypeASRService(),
            workspaceBootstrapService: WorkspaceBootstrapService(
                apiClient: apiClient,
                settingsStore: settingsStore
            ),
            meetingSyncService: syncService
        )

        let meeting = try repository.createDraftMeeting(hiddenWorkspaceID: "workspace-1")
        meeting.title = "候选人访谈"
        meeting.userNotesPlainText = "已有人物背景和关键问题。"
        meeting.enhancedNotes = "旧的通用 AI 笔记"
        try repository.save()

        var enhanceCalls = 0
        MeetingTypeAutoRefreshMockURLProtocol.requestHandler = { request in
            let url = try #require(request.url)
            let response = try #require(
                HTTPURLResponse(
                    url: url,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                )
            )

            switch url.path {
            case "/api/enhance":
                enhanceCalls += 1
                let body = try requestBodyData(from: request)
                let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
                let promptOptions = try #require(json["promptOptions"] as? [String: Any])
                #expect(promptOptions["meetingType"] as? String == "访谈")

                let payload: [String: Any] = [
                    "content": "## 受访者核心观点\n- 「我来负责下周五前整理访谈报告。」",
                    "provider": "test"
                ]
                return (response, try JSONSerialization.data(withJSONObject: payload))

            default:
                throw URLError(.unsupportedURL)
            }
        }

        store.updateMeetingType(MeetingTypeOption.interview.rawValue, for: meeting)

        try await waitUntil {
            enhanceCalls == 1
                && ((try? repository.meeting(withID: meeting.id))??.enhancedNotes.contains("受访者核心观点") == true)
        }

        let refreshedMeeting = try #require(try repository.meeting(withID: meeting.id))
        #expect(refreshedMeeting.meetingType == "访谈")
        #expect(refreshedMeeting.enhancedNotes.contains("受访者核心观点"))
        #expect(syncService.syncedMeetingIDs == [meeting.id])
    }

    @MainActor
    @Test
    func changingMeetingTypeWithoutExistingEnhancedNotesOnlyPersistsType() async throws {
        MeetingTypeAutoRefreshMockURLProtocol.reset()
        defer { MeetingTypeAutoRefreshMockURLProtocol.reset() }

        let container = try ModelContainerFactory.makeContainer(inMemory: true)
        let repository = MeetingRepository(modelContext: container.mainContext)
        let chatRepository = ChatSessionRepository(modelContext: container.mainContext)
        let settingsStore = makeSettingsStore()
        settingsStore.hiddenWorkspaceID = "workspace-1"
        settingsStore.workspaceBootstrapState = .success
        settingsStore.markBackendReachable()
        let apiClient = makeAPIClient(settingsStore: settingsStore)
        let syncService = StubMeetingTypeSyncService()

        let store = MeetingStore(
            repository: repository,
            chatSessionRepository: chatRepository,
            settingsStore: settingsStore,
            recordingSessionStore: RecordingSessionStore(),
            appActivityCoordinator: AppActivityCoordinator(),
            recordingLiveActivityCoordinator: NoopMeetingTypeRecordingLiveActivityCoordinator(),
            audioRecorderService: NoopMeetingTypeAudioRecorderService(),
            audioFileTranscriptionService: NoopMeetingTypeAudioFileTranscriptionService(),
            apiClient: apiClient,
            asrService: NoopMeetingTypeASRService(),
            workspaceBootstrapService: WorkspaceBootstrapService(
                apiClient: apiClient,
                settingsStore: settingsStore
            ),
            meetingSyncService: syncService
        )

        let meeting = try repository.createDraftMeeting(hiddenWorkspaceID: "workspace-1")
        meeting.title = "还没生成 AI 笔记"
        meeting.userNotesPlainText = "只是先选一个类型。"
        meeting.enhancedNotes = ""
        try repository.save()

        var enhanceCalls = 0
        MeetingTypeAutoRefreshMockURLProtocol.requestHandler = { request in
            enhanceCalls += 1
            let response = try #require(
                HTTPURLResponse(
                    url: request.url ?? URL(string: "https://example.com/api/enhance")!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                )
            )
            let payload: [String: Any] = [
                "content": "不应该被调用",
                "provider": "test"
            ]
            return (response, try JSONSerialization.data(withJSONObject: payload))
        }

        store.updateMeetingType(MeetingTypeOption.speech.rawValue, for: meeting)
        try await Task.sleep(nanoseconds: 200_000_000)

        let refreshedMeeting = try #require(try repository.meeting(withID: meeting.id))
        #expect(refreshedMeeting.meetingType == "演讲")
        #expect(refreshedMeeting.enhancedNotes.isEmpty)
        #expect(enhanceCalls == 0)
        #expect(syncService.syncedMeetingIDs.isEmpty)
    }

    @MainActor
    private func makeSettingsStore() -> SettingsStore {
        let suiteName = "piedras.tests.meeting-type.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return SettingsStore(
            defaults: defaults,
            debugDefaultBackendBaseURLString: "https://example.com"
        )
    }

    @MainActor
    private func makeAPIClient(settingsStore: SettingsStore) -> APIClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MeetingTypeAutoRefreshMockURLProtocol.self]
        return APIClient(
            settingsStore: settingsStore,
            session: URLSession(configuration: configuration)
        )
    }

    private func requestBodyData(from request: URLRequest) throws -> Data {
        if let body = request.httpBody {
            return body
        }

        guard let stream = request.httpBodyStream else {
            throw URLError(.badServerResponse)
        }

        stream.open()
        defer { stream.close() }

        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)

        while stream.hasBytesAvailable {
            let bytesRead = stream.read(&buffer, maxLength: buffer.count)

            if bytesRead < 0 {
                throw stream.streamError ?? URLError(.cannotParseResponse)
            }

            if bytesRead == 0 {
                break
            }

            data.append(contentsOf: buffer.prefix(bytesRead))
        }

        return data
    }

    @MainActor
    private func waitUntil(
        timeoutNanoseconds: UInt64 = 1_500_000_000,
        pollNanoseconds: UInt64 = 20_000_000,
        condition: @escaping @MainActor () -> Bool
    ) async throws {
        let deadline = ContinuousClock.now + .nanoseconds(timeoutNanoseconds)
        while !condition() {
            if ContinuousClock.now >= deadline {
                Issue.record("Condition not met before timeout")
                throw CancellationError()
            }
            try await Task.sleep(nanoseconds: pollNanoseconds)
        }
    }
}
