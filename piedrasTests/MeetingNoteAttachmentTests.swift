import Foundation
import SwiftData
import Testing
import UIKit
@testable import piedras

private struct MockMeetingNoteAttachmentImageTextExtractor: AnnotationImageTextExtracting {
    let extractedText: String

    func extractText(from imageURLs: [URL]) async throws -> String {
        #expect(!imageURLs.isEmpty)
        return extractedText
    }
}

@MainActor
private final class NoopMeetingNoteAttachmentAudioRecorderService: AudioRecorderServicing {
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
            fileURL: URL(fileURLWithPath: "/tmp/meeting-note-attachment-start.m4a"),
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
            fileURL: URL(fileURLWithPath: "/tmp/meeting-note-attachment-stop.m4a"),
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
private final class NoopMeetingNoteAttachmentASRService: ASRServicing {
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
private final class NoopMeetingNoteAttachmentAudioFileTranscriptionService: AudioFileTranscriptionServicing {
    func transcribe(
        fileURL: URL,
        workspaceID: String?,
        onPhaseChange: @escaping @MainActor (AudioFileTranscriptionPhase) -> Void,
        onPartialText: @escaping @MainActor (String) -> Void,
        onFinalResult: @escaping @MainActor (ASRFinalResult) -> Void
    ) async throws {}
}

@MainActor
private final class NoopMeetingNoteAttachmentLiveActivityCoordinator: RecordingLiveActivityCoordinating {
    func start(meetingID: String, phase: RecordingLiveActivityPhase, durationSeconds: Int) {}
    func update(phase: RecordingLiveActivityPhase, durationSeconds: Int) {}
    func end() {}
}

@MainActor
private final class StubMeetingNoteAttachmentSyncService: MeetingSyncServicing {
    func syncPendingMeetings() async -> MeetingSyncBatchResult {
        .init(syncedCount: 0, failedCount: 0)
    }

    func syncMeeting(id: String) async throws {}
    func refreshRemoteMeetings() async throws -> Int { 0 }
}

struct MeetingNoteAttachmentTests {
    @Test
    func meetingDefaultsKeepNoteAttachmentFieldsEmpty() {
        let meeting = Meeting()

        #expect(meeting.noteAttachmentFileNames.isEmpty)
        #expect(meeting.noteAttachmentAssetIdentifiersByFileName.isEmpty)
        #expect(meeting.noteAttachmentTextContext.isEmpty)
        #expect(meeting.noteAttachmentTextStatus == .idle)
        #expect(meeting.noteAttachmentTextUpdatedAt == nil)
    }

    @MainActor
    @Test
    func addingMeetingNoteAttachmentExtractsTextAndMarksRefreshHintWithoutAutoGenerating() async throws {
        let container = try ModelContainerFactory.makeContainer(inMemory: true)
        let repository = MeetingRepository(modelContext: container.mainContext)
        let chatRepository = ChatSessionRepository(modelContext: container.mainContext)
        let settingsStore = makeSettingsStore()
        let apiClient = APIClient(settingsStore: settingsStore)

        let store = MeetingStore(
            repository: repository,
            chatSessionRepository: chatRepository,
            settingsStore: settingsStore,
            recordingSessionStore: RecordingSessionStore(),
            appActivityCoordinator: AppActivityCoordinator(),
            recordingLiveActivityCoordinator: NoopMeetingNoteAttachmentLiveActivityCoordinator(),
            audioRecorderService: NoopMeetingNoteAttachmentAudioRecorderService(),
            audioFileTranscriptionService: NoopMeetingNoteAttachmentAudioFileTranscriptionService(),
            apiClient: apiClient,
            asrService: NoopMeetingNoteAttachmentASRService(),
            workspaceBootstrapService: WorkspaceBootstrapService(
                apiClient: apiClient,
                settingsStore: settingsStore
            ),
            meetingSyncService: StubMeetingNoteAttachmentSyncService(),
            noteAttachmentImageTextExtractor: MockMeetingNoteAttachmentImageTextExtractor(
                extractedText: "白板写着：4 月 8 日灰度发布。"
            )
        )

        let meeting = try repository.createDraftMeeting(hiddenWorkspaceID: nil)
        meeting.enhancedNotes = "现有 AI 笔记"
        try repository.save()
        defer { MeetingNoteAttachmentStorage.deleteAllAttachments(meetingID: meeting.id) }

        store.addNoteAttachment(makeTestImage(), to: meeting)

        try await waitUntil {
            meeting.noteAttachmentTextStatus == .ready
                && meeting.noteAttachmentFileNames.count == 1
        }

        #expect(meeting.noteAttachmentTextContext.contains("4 月 8 日灰度发布"))
        #expect(meeting.aiNotesFreshnessState == .staleFromAttachments)
        #expect(meeting.enhancedNotes == "现有 AI 笔记")
    }

    @MainActor
    @Test
    func addingSamePhotoAssetTwiceOnlyKeepsOneAttachment() async throws {
        let container = try ModelContainerFactory.makeContainer(inMemory: true)
        let repository = MeetingRepository(modelContext: container.mainContext)
        let chatRepository = ChatSessionRepository(modelContext: container.mainContext)
        let store = makeStore(repository: repository, chatRepository: chatRepository)

        let meeting = try repository.createDraftMeeting(hiddenWorkspaceID: nil)
        defer { MeetingNoteAttachmentStorage.deleteAllAttachments(meetingID: meeting.id) }

        let firstResult = store.addNoteAttachment(
            makeTestImage(),
            to: meeting,
            assetIdentifier: "ph://asset-1"
        )
        let secondResult = store.addNoteAttachment(
            makeTestImage(),
            to: meeting,
            assetIdentifier: "ph://asset-1"
        )

        try await waitUntil {
            meeting.noteAttachmentFileNames.count == 1
        }

        #expect(firstResult == .added)
        #expect(secondResult == .skippedDuplicate)
        #expect(meeting.noteAttachmentFileNames.count == 1)
        #expect(meeting.noteAttachmentAssetIdentifiersByFileName.count == 1)
        #expect(meeting.noteAttachmentAssetIdentifiersByFileName.values.sorted() == ["ph://asset-1"])
    }

    @MainActor
    @Test
    func deletingPhotoAssetAllowsAddingItAgain() async throws {
        let container = try ModelContainerFactory.makeContainer(inMemory: true)
        let repository = MeetingRepository(modelContext: container.mainContext)
        let chatRepository = ChatSessionRepository(modelContext: container.mainContext)
        let store = makeStore(repository: repository, chatRepository: chatRepository)

        let meeting = try repository.createDraftMeeting(hiddenWorkspaceID: nil)
        defer { MeetingNoteAttachmentStorage.deleteAllAttachments(meetingID: meeting.id) }

        let firstResult = store.addNoteAttachment(
            makeTestImage(),
            to: meeting,
            assetIdentifier: "ph://asset-2"
        )
        try await waitUntil {
            meeting.noteAttachmentFileNames.count == 1
        }
        let firstFileName = try #require(meeting.noteAttachmentFileNames.first)

        store.removeNoteAttachment(fileName: firstFileName, from: meeting)

        let secondResult = store.addNoteAttachment(
            makeTestImage(),
            to: meeting,
            assetIdentifier: "ph://asset-2"
        )

        try await waitUntil {
            meeting.noteAttachmentFileNames.count == 1
        }

        #expect(firstResult == .added)
        #expect(secondResult == .added)
        #expect(meeting.noteAttachmentFileNames.count == 1)
        #expect(meeting.noteAttachmentAssetIdentifiersByFileName.count == 1)
        #expect(meeting.noteAttachmentAssetIdentifiersByFileName.values.sorted() == ["ph://asset-2"])
    }

    @MainActor
    @Test
    func cameraStyleAttachmentsRemainAddableWithoutAssetIdentifier() async throws {
        let container = try ModelContainerFactory.makeContainer(inMemory: true)
        let repository = MeetingRepository(modelContext: container.mainContext)
        let chatRepository = ChatSessionRepository(modelContext: container.mainContext)
        let store = makeStore(repository: repository, chatRepository: chatRepository)

        let meeting = try repository.createDraftMeeting(hiddenWorkspaceID: nil)
        defer { MeetingNoteAttachmentStorage.deleteAllAttachments(meetingID: meeting.id) }

        let firstResult = store.addNoteAttachment(makeTestImage(), to: meeting, assetIdentifier: nil)
        let secondResult = store.addNoteAttachment(makeTestImage(), to: meeting, assetIdentifier: nil)

        try await waitUntil {
            meeting.noteAttachmentFileNames.count == 2
        }

        #expect(firstResult == .added)
        #expect(secondResult == .added)
        #expect(meeting.noteAttachmentFileNames.count == 2)
        #expect(meeting.noteAttachmentAssetIdentifiersByFileName.isEmpty)
    }

    @MainActor
    private func makeSettingsStore() -> SettingsStore {
        let suiteName = "piedras.tests.meeting-note-attachment.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return SettingsStore(defaults: defaults)
    }

    @MainActor
    private func makeStore(
        repository: MeetingRepository,
        chatRepository: ChatSessionRepository
    ) -> MeetingStore {
        let settingsStore = makeSettingsStore()
        let apiClient = APIClient(settingsStore: settingsStore)

        return MeetingStore(
            repository: repository,
            chatSessionRepository: chatRepository,
            settingsStore: settingsStore,
            recordingSessionStore: RecordingSessionStore(),
            appActivityCoordinator: AppActivityCoordinator(),
            recordingLiveActivityCoordinator: NoopMeetingNoteAttachmentLiveActivityCoordinator(),
            audioRecorderService: NoopMeetingNoteAttachmentAudioRecorderService(),
            audioFileTranscriptionService: NoopMeetingNoteAttachmentAudioFileTranscriptionService(),
            apiClient: apiClient,
            asrService: NoopMeetingNoteAttachmentASRService(),
            workspaceBootstrapService: WorkspaceBootstrapService(
                apiClient: apiClient,
                settingsStore: settingsStore
            ),
            meetingSyncService: StubMeetingNoteAttachmentSyncService(),
            noteAttachmentImageTextExtractor: MockMeetingNoteAttachmentImageTextExtractor(
                extractedText: "白板写着：4 月 8 日灰度发布。"
            )
        )
    }

    @MainActor
    private func waitUntil(
        timeoutNanoseconds: UInt64 = 2_000_000_000,
        pollNanoseconds: UInt64 = 20_000_000,
        condition: @escaping @MainActor () -> Bool
    ) async throws {
        let deadline = ContinuousClock.now + .nanoseconds(timeoutNanoseconds)
        while !condition() {
            guard ContinuousClock.now < deadline else {
                throw NSError(domain: "MeetingNoteAttachmentTests", code: 1)
            }
            try await Task.sleep(nanoseconds: pollNanoseconds)
        }
    }

    @MainActor
    private func makeTestImage() -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 48, height: 36))
        return renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 48, height: 36))
            UIColor.black.setFill()
            context.fill(CGRect(x: 6, y: 6, width: 36, height: 24))
        }
    }
}
