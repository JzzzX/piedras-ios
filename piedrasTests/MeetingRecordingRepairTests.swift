import Foundation
import SwiftData
import SwiftUI
import Testing
@testable import piedras

@MainActor
private final class StubAudioFileTranscriptionService: AudioFileTranscriptionServicing {
    enum Behavior {
        case succeed([ASRFinalResult])
        case fail(String)
    }

    var behavior: Behavior
    private(set) var transcribeCalls = 0

    init(behavior: Behavior) {
        self.behavior = behavior
    }

    func transcribe(
        fileURL: URL,
        workspaceID: String?,
        onPhaseChange: @escaping @MainActor (AudioFileTranscriptionPhase) -> Void,
        onPartialText: @escaping @MainActor (String) -> Void,
        onFinalResult: @escaping @MainActor (ASRFinalResult) -> Void
    ) async throws {
        transcribeCalls += 1
        onPhaseChange(.preparing)
        onPhaseChange(.connecting)

        switch behavior {
        case let .succeed(results):
            onPartialText("partial")
            for result in results {
                onFinalResult(result)
            }
            onPartialText("")
        case let .fail(message):
            throw APIClientError.requestFailed(message)
        }
    }
}

@MainActor
private final class StubASRService: ASRServicing {
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
private final class StubMeetingSyncService: MeetingSyncServicing {
    private let repository: MeetingRepository

    private(set) var syncedMeetingIDs: [String] = []
    private(set) var transcriptSnapshotsAtSync: [String] = []

    init(repository: MeetingRepository) {
        self.repository = repository
    }

    func syncPendingMeetings() async -> MeetingSyncBatchResult {
        .init(syncedCount: 0, failedCount: 0)
    }

    func syncMeeting(id: String) async throws {
        syncedMeetingIDs.append(id)
        let transcript = try repository.meeting(withID: id)?.transcriptText ?? ""
        transcriptSnapshotsAtSync.append(transcript)
    }

    func refreshRemoteMeetings() async throws -> Int {
        0
    }
}

@Suite(.serialized)
struct MeetingRecordingRepairTests {
    @MainActor
    @Test
    func backgroundingActiveRecordingMarksTranscriptForRepair() async throws {
        let fixture = try makeFixture(transcriptionBehavior: .succeed([]))
        let meeting = try fixture.repository.createDraftMeeting(hiddenWorkspaceID: "workspace-1")
        fixture.meetingStore.loadMeetings()

        fixture.recordingSessionStore.meetingID = meeting.id
        fixture.recordingSessionStore.phase = .recording

        fixture.meetingStore.handleScenePhaseChange(.background)

        #expect(fixture.recordingSessionStore.needsTranscriptRepairAfterStop)
    }

    @MainActor
    @Test
    func stopRecordingWithCoverageGapRepairsTranscriptBeforeSync() async throws {
        let repairedResult = ASRFinalResult(
            text: "完整补转写",
            startTime: 0,
            endTime: 3_000
        )
        let fixture = try makeFixture(transcriptionBehavior: .succeed([repairedResult]))
        let meeting = try fixture.repository.createDraftMeeting(hiddenWorkspaceID: "workspace-1")
        meeting.title = "已有标题"
        meeting.enhancedNotes = "已有 AI 笔记"
        meeting.recordingMode = .microphone
        meeting.segments = [
            TranscriptSegment(
                speaker: "麦克风",
                text: "残缺实时转写",
                startTime: 0,
                endTime: 1_000,
                orderIndex: 0
            )
        ]
        try fixture.repository.save()
        fixture.meetingStore.loadMeetings()

        fixture.recordingSessionStore.meetingID = meeting.id
        fixture.recordingSessionStore.phase = .recording
        fixture.recordingSessionStore.markTranscriptCoverageGap()

        let audioURL = try makeTemporaryAudioFile(named: "recording-repair-success.m4a")
        defer { try? FileManager.default.removeItem(at: audioURL) }

        await fixture.meetingStore.finishStoppedRecording(
            meetingID: meeting.id,
            artifact: LocalAudioArtifact(
                fileURL: audioURL,
                durationSeconds: 16,
                mimeType: "audio/m4a"
            )
        )

        let refreshedMeeting = try #require(try fixture.repository.meeting(withID: meeting.id))
        #expect(refreshedMeeting.status == .ended)
        #expect(refreshedMeeting.orderedSegments.map(\.text) == ["完整补转写"])
        #expect(fixture.transcriber.transcribeCalls == 1)
        #expect(fixture.syncService.syncedMeetingIDs == [meeting.id])
        #expect(fixture.syncService.transcriptSnapshotsAtSync == ["完整补转写"])
        #expect(fixture.recordingSessionStore.phase == .idle)
        #expect(fixture.recordingSessionStore.needsTranscriptRepairAfterStop == false)
        #expect(fixture.meetingStore.fileTranscriptionStatus(meetingID: meeting.id) == nil)
    }

    @MainActor
    @Test
    func stopRecordingWithCoverageGapFailureDoesNotSyncOrGenerateAi() async throws {
        let fixture = try makeFixture(transcriptionBehavior: .fail("repair failed"))
        let meeting = try fixture.repository.createDraftMeeting(hiddenWorkspaceID: "workspace-1")
        meeting.title = "已有标题"
        meeting.enhancedNotes = "已有 AI 笔记"
        meeting.recordingMode = .microphone
        meeting.segments = [
            TranscriptSegment(
                speaker: "麦克风",
                text: "残缺实时转写",
                startTime: 0,
                endTime: 1_000,
                orderIndex: 0
            )
        ]
        try fixture.repository.save()
        fixture.meetingStore.loadMeetings()

        fixture.recordingSessionStore.meetingID = meeting.id
        fixture.recordingSessionStore.phase = .recording
        fixture.recordingSessionStore.markTranscriptCoverageGap()

        let audioURL = try makeTemporaryAudioFile(named: "recording-repair-failure.m4a")
        defer { try? FileManager.default.removeItem(at: audioURL) }

        await fixture.meetingStore.finishStoppedRecording(
            meetingID: meeting.id,
            artifact: LocalAudioArtifact(
                fileURL: audioURL,
                durationSeconds: 8,
                mimeType: "audio/m4a"
            )
        )

        let refreshedMeeting = try #require(try fixture.repository.meeting(withID: meeting.id))
        #expect(refreshedMeeting.status == .transcriptionFailed)
        #expect(refreshedMeeting.orderedSegments.map(\.text) == ["残缺实时转写"])
        #expect(fixture.syncService.syncedMeetingIDs.isEmpty)
        let status = try #require(fixture.meetingStore.fileTranscriptionStatus(meetingID: meeting.id))
        #expect(status.canRetry)
        #expect(fixture.meetingStore.lastErrorMessage == "repair failed")
    }

    @MainActor
    private func makeFixture(
        transcriptionBehavior: StubAudioFileTranscriptionService.Behavior
    ) throws -> (
        container: ModelContainer,
        meetingStore: MeetingStore,
        repository: MeetingRepository,
        settingsStore: SettingsStore,
        recordingSessionStore: RecordingSessionStore,
        transcriber: StubAudioFileTranscriptionService,
        syncService: StubMeetingSyncService
    ) {
        let container = try ModelContainerFactory.makeContainer(inMemory: true)
        let repository = MeetingRepository(modelContext: container.mainContext)
        let chatRepository = ChatSessionRepository(modelContext: container.mainContext)
        let settingsStore = makeSettingsStore()
        settingsStore.hiddenWorkspaceID = "workspace-1"
        settingsStore.workspaceBootstrapState = .success
        settingsStore.markBackendReachable()
        let recordingSessionStore = RecordingSessionStore()
        let apiClient = APIClient(settingsStore: settingsStore)
        let transcriber = StubAudioFileTranscriptionService(behavior: transcriptionBehavior)
        let syncService = StubMeetingSyncService(repository: repository)
        let meetingStore = MeetingStore(
            repository: repository,
            chatSessionRepository: chatRepository,
            settingsStore: settingsStore,
            recordingSessionStore: recordingSessionStore,
            appActivityCoordinator: AppActivityCoordinator(),
            audioRecorderService: AudioRecorderService(sessionCoordinator: AudioSessionCoordinator()),
            audioFileTranscriptionService: transcriber,
            apiClient: apiClient,
            asrService: StubASRService(),
            workspaceBootstrapService: WorkspaceBootstrapService(
                apiClient: apiClient,
                settingsStore: settingsStore
            ),
            meetingSyncService: syncService
        )
        return (
            container,
            meetingStore,
            repository,
            settingsStore,
            recordingSessionStore,
            transcriber,
            syncService
        )
    }

    @MainActor
    private func makeSettingsStore() -> SettingsStore {
        let suiteName = "piedras.tests.recording.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return SettingsStore(
            defaults: defaults,
            debugDefaultBackendBaseURLString: "https://example.com"
        )
    }

    private func makeTemporaryAudioFile(named name: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent(name)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("audio".utf8).write(to: url)
        return url
    }
}
