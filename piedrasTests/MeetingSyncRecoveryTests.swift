import Foundation
import SwiftData
import Testing
@testable import piedras

private final class SyncRecoveryMockURLProtocol: URLProtocol {
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

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
private final class SyncRecoveryStubAudioFileTranscriptionService: AudioFileTranscriptionServicing {
    func transcribe(
        fileURL: URL,
        workspaceID: String?,
        onPhaseChange: @escaping @MainActor (AudioFileTranscriptionPhase) -> Void,
        onPartialText: @escaping @MainActor (String) -> Void,
        onFinalResult: @escaping @MainActor (ASRFinalResult) -> Void
    ) async throws {}
}

@MainActor
private final class SyncRecoveryStubASRService: ASRServicing {
    var onPartialText: ((String) -> Void)?
    var onFinalResult: ((ASRFinalResult) -> Void)?
    var onRecognitionSnapshot: ((ASRRecognitionSnapshot) -> Void)?
    var onStateChange: ((ASRConnectionState) -> Void)?
    var onError: ((String) -> Void)?
    var onTransportEvent: ((String) -> Void)?
    var onPCMChunkSent: ((Int) -> Void)?

    func startStreaming(workspaceID: String?, meetingID: String?) async throws {}
    func enqueuePCM(_ data: Data) {}
    func stopStreaming() async {}
}

@MainActor
private final class SyncRecoveryStubAudioRecorderService: AudioRecorderServicing {
    var onProgress: ((Double, Int) -> Void)?
    var onPCMData: ((Data) -> Void)?
    var onCaptureStateChange: ((String) -> Void)?
    var onSourcePlaybackUpdate: ((TimeInterval, TimeInterval, Bool, String?) -> Void)?
    var onLifecycleEvent: ((AudioSessionLifecycleEvent) -> Void)?

    func startRecording(meetingID: String, sourceAudio: SourceAudioAsset?) async throws -> RecordingStartArtifact {
        RecordingStartArtifact(
            fileURL: URL(fileURLWithPath: "/tmp/unused.m4a"),
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
            fileURL: URL(fileURLWithPath: "/tmp/unused.m4a"),
            durationSeconds: 0,
            mimeType: "audio/m4a"
        )
    }
    func toggleSourceAudioPlayback() throws {}
    func reconcileForegroundRecording() -> AudioRecorderForegroundRecoveryResult { .healthy }
    func currentRecordingDurationSeconds() -> Int { 0 }
    func makeRecordingSnapshot() throws -> RecordingSnapshotArtifact? { nil }
}

@MainActor
private final class SyncRecoveryStubRecordingLiveActivityCoordinator: RecordingLiveActivityCoordinating {
    func start(meetingID: String, phase: RecordingLiveActivityPhase, durationSeconds: Int) {}
    func update(phase: RecordingLiveActivityPhase, durationSeconds: Int) {}
    func end() {}
}

@MainActor
private final class ControlledMeetingSyncService: MeetingSyncServicing {
    var pendingResults: [MeetingSyncBatchResult]
    var refreshResults: [Result<Int, Error>]
    private(set) var syncPendingCallCount = 0

    init(
        pendingResults: [MeetingSyncBatchResult],
        refreshResults: [Result<Int, Error>]
    ) {
        self.pendingResults = pendingResults
        self.refreshResults = refreshResults
    }

    func syncPendingMeetings() async -> MeetingSyncBatchResult {
        syncPendingCallCount += 1
        if pendingResults.isEmpty {
            return .init(syncedCount: 0, failedCount: 0)
        }

        return pendingResults.removeFirst()
    }

    func syncMeeting(id: String) async throws {}

    func refreshRemoteMeetings() async throws -> Int {
        if refreshResults.isEmpty {
            return 0
        }

        return try refreshResults.removeFirst().get()
    }
}

@Suite(.serialized)
struct MeetingSyncRecoveryTests {
    @MainActor
    @Test
    func repairCloudStateRetriesFailedBatchUntilSuccess() async throws {
        let container = try ModelContainerFactory.makeContainer(inMemory: true)
        let repository = MeetingRepository(modelContext: container.mainContext)
        let chatRepository = ChatSessionRepository(modelContext: container.mainContext)
        let settingsStore = makeSettingsStore()
        settingsStore.hiddenWorkspaceID = "workspace-1"
        settingsStore.workspaceBootstrapState = .success
        settingsStore.markBackendReachable()
        let recordingSessionStore = RecordingSessionStore()
        let apiClient = makeAPIClient(settingsStore: settingsStore)
        defer { SyncRecoveryMockURLProtocol.requestHandler = nil }
        let syncService = ControlledMeetingSyncService(
            pendingResults: [
                .init(syncedCount: 0, failedCount: 1),
                .init(syncedCount: 1, failedCount: 0),
            ],
            refreshResults: [
                .success(0),
                .success(1),
            ]
        )
        let meetingStore = MeetingStore(
            repository: repository,
            chatSessionRepository: chatRepository,
            settingsStore: settingsStore,
            recordingSessionStore: recordingSessionStore,
            appActivityCoordinator: AppActivityCoordinator(),
            recordingLiveActivityCoordinator: SyncRecoveryStubRecordingLiveActivityCoordinator(),
            audioRecorderService: SyncRecoveryStubAudioRecorderService(),
            audioFileTranscriptionService: SyncRecoveryStubAudioFileTranscriptionService(),
            apiClient: apiClient,
            asrService: SyncRecoveryStubASRService(),
            workspaceBootstrapService: WorkspaceBootstrapService(
                apiClient: apiClient,
                settingsStore: settingsStore
            ),
            meetingSyncService: syncService,
            syncRecoveryRetryDelays: [.zero]
        )

        let meeting = try repository.createDraftMeeting(hiddenWorkspaceID: "workspace-1")
        meeting.status = .ended
        meeting.syncState = .pending
        try repository.save()
        meetingStore.loadMeetings()

        await meetingStore.repairCloudState()
        await waitFor(
            description: "second sync attempt",
            timeoutMS: 500
        ) {
            syncService.syncPendingCallCount >= 2
        }

        #expect(syncService.syncPendingCallCount == 2)
        #expect(settingsStore.syncIssueKind == nil)
        #expect(settingsStore.syncRetryCount == 0)
        #expect(settingsStore.requiresSyncRecoveryAttention == false)
        #expect(settingsStore.lastSuccessfulSyncAt != nil)
        #expect(settingsStore.syncStatusMessage.contains("推送 1 条"))
    }

    @MainActor
    private func makeSettingsStore() -> SettingsStore {
        let suiteName = "piedras.tests.sync-recovery.\(UUID().uuidString)"
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
        configuration.protocolClasses = [SyncRecoveryMockURLProtocol.self]
        SyncRecoveryMockURLProtocol.requestHandler = { request in
            let url = try #require(request.url)
            let response = try #require(
                HTTPURLResponse(
                    url: url,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                )
            )

            return (
                response,
                Data(
                    #"{"ok":true,"database":true,"startupBootstrap":{"ready":true,"status":"ready","attempts":1,"startedAt":"2026-03-31T00:00:00.000Z","completedAt":"2026-03-31T00:00:01.000Z","lastError":null,"schemaReady":true,"missingItems":[],"legacyUsers":[],"retryScheduled":false,"retryAt":null},"checkedAt":"2026-03-31T00:00:02.000Z"}"#.utf8
                )
            )
        }
        return APIClient(
            settingsStore: settingsStore,
            session: URLSession(configuration: configuration)
        )
    }

    @MainActor
    private func waitFor(
        description: String,
        timeoutMS: UInt64,
        until predicate: @escaping @MainActor () -> Bool
    ) async {
        let deadline = ContinuousClock.now + .milliseconds(timeoutMS)
        while !predicate() {
            if ContinuousClock.now >= deadline {
                Issue.record("Timed out waiting for \(description)")
                return
            }

            try? await Task.sleep(for: .milliseconds(10))
        }
    }
}
