import Foundation
import Observation
import SwiftUI
import UIKit

struct FileTranscriptionStatusSnapshot: Equatable {
    let phase: AudioFileTranscriptionPhase?
    let errorMessage: String?
    let showsFailure: Bool

    init(
        phase: AudioFileTranscriptionPhase?,
        errorMessage: String?,
        showsFailure: Bool = false
    ) {
        self.phase = phase
        self.errorMessage = errorMessage
        self.showsFailure = showsFailure
    }

    var isActive: Bool {
        phase != nil && !showsFailure
    }

    var canRetry: Bool {
        showsFailure
    }

    var displayMessage: String {
        if showsFailure {
            return AppStrings.current.audioTranscriptionFailed
        }

        guard let phase else {
            return ""
        }

        switch phase {
        case .preparing:
            return AppStrings.current.preparingImportedAudio
        case .connecting:
            return AppStrings.current.connectingASR
        case let .transcribing(elapsed, total):
            return AppStrings.current.transcribingAudioProgress(
                elapsed: elapsed.mmss,
                total: max(total, elapsed).mmss
            )
        case .finalizing:
            return AppStrings.current.finalizingTranscription
        }
    }
}

private struct BackgroundTranscriptChunk {
    let pcmData: Data
    let startTimeMS: Double
    let durationMS: Double
}

@MainActor
@Observable
final class MeetingStore {
    private static let backgroundChunkTargetDurationMS = 12_000.0
    private static let backgroundShadowBufferMaxDurationMS = 60_000.0
    private static let backgroundChunkRetryDelay: Duration = .milliseconds(300)
    private static let maxNoteAttachmentsPerMeeting = 10
    private static let asrReconnectDelays: [Duration] = [
        .seconds(2),
        .seconds(4),
        .seconds(8),
        .seconds(10),
    ]

    private let repository: MeetingRepository
    private let chatSessionRepository: ChatSessionRepository
    private let settingsStore: SettingsStore
    private let recordingSessionStore: RecordingSessionStore
    private let appActivityCoordinator: AppActivityCoordinator
    private let recordingLiveActivityCoordinator: any RecordingLiveActivityCoordinating
    private let audioRecorderService: any AudioRecorderServicing
    private let audioFileTranscriptionService: any AudioFileTranscriptionServicing
    private let apiClient: APIClient
    private let asrService: any ASRServicing
    private let workspaceBootstrapService: WorkspaceBootstrapService
    private let meetingSyncService: any MeetingSyncServicing
    private let noteAttachmentImageTextExtractor: any AnnotationImageTextExtracting

    var meetings: [Meeting] = []
    var selectedMeetingID: String?
    var searchText = "" {
        didSet {
            loadMeetings()
        }
    }
    var isLoading = false
    var lastErrorMessage: String?
    var enhancingMeetingIDs: Set<String> = []
    var generatingTitleMeetingIDs: Set<String> = []
    var streamingChatMeetingIDs: Set<String> = []
    var transcribingMeetingIDs: Set<String> = []
    var activeChatSessionIDs: [String: String] = [:]
    var draftChatMeetingIDs: Set<String> = []
    private var didLoad = false
    private var didStartBackendPreparation = false
    private var backendPreparationTask: Task<Void, Never>?
    private var asrReconnectTask: Task<Void, Never>?
    private var asrReconnectAttempt = 0
    private var scheduledSyncTasks: [String: Task<Void, Never>] = [:]
    private var fileTranscriptionTasks: [String: Task<Void, Never>] = [:]
    private var chatStreamingTasks: [String: Task<Bool, Never>] = [:]
    private var backgroundTranscriptBackfillTask: Task<Void, Never>?
    private var noteAttachmentTextTasks: [String: Task<Void, Never>] = [:]
    private var noteAttachmentTaskTokens: [String: UUID] = [:]
    private var backgroundTranscriptPCMBuffer = Data()
    private var backgroundShadowBufferStartTimeMS: Double?
    private var shouldFlushBackgroundTranscriptTail = false
    private var lastPublishedLiveActivityDurationSeconds: Int?
    private var fileTranscriptionStatuses: [String: FileTranscriptionStatusSnapshot] = [:]
    private var fileTranscriptionPartials: [String: String] = [:]
    private let isUITestRuntime = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        || ProcessInfo.processInfo.arguments.contains { $0.hasPrefix("UITEST_") }

    init(
        repository: MeetingRepository,
        chatSessionRepository: ChatSessionRepository,
        settingsStore: SettingsStore,
        recordingSessionStore: RecordingSessionStore,
        appActivityCoordinator: AppActivityCoordinator,
        recordingLiveActivityCoordinator: any RecordingLiveActivityCoordinating,
        audioRecorderService: any AudioRecorderServicing,
        audioFileTranscriptionService: any AudioFileTranscriptionServicing,
        apiClient: APIClient,
        asrService: any ASRServicing,
        workspaceBootstrapService: WorkspaceBootstrapService,
        meetingSyncService: any MeetingSyncServicing,
        noteAttachmentImageTextExtractor: any AnnotationImageTextExtracting = VisionAnnotationImageTextExtractor()
    ) {
        self.repository = repository
        self.chatSessionRepository = chatSessionRepository
        self.settingsStore = settingsStore
        self.recordingSessionStore = recordingSessionStore
        self.appActivityCoordinator = appActivityCoordinator
        self.recordingLiveActivityCoordinator = recordingLiveActivityCoordinator
        self.audioRecorderService = audioRecorderService
        self.audioFileTranscriptionService = audioFileTranscriptionService
        self.apiClient = apiClient
        self.asrService = asrService
        self.workspaceBootstrapService = workspaceBootstrapService
        self.meetingSyncService = meetingSyncService
        self.noteAttachmentImageTextExtractor = noteAttachmentImageTextExtractor

        self.audioRecorderService.onProgress = { [weak self] level, duration in
            self?.handleRecordingProgress(level: level, duration: duration)
        }
        self.audioRecorderService.onCaptureStateChange = { [weak self] state in
            self?.recordingSessionStore.audioCaptureState = state
        }
        self.audioRecorderService.onSourcePlaybackUpdate = { [weak self] currentTime, duration, isPlaying, displayName in
            self?.recordingSessionStore.sourceAudioDisplayName = displayName
            self?.recordingSessionStore.updateSourceAudioPlayback(
                currentTime: currentTime,
                duration: duration,
                isPlaying: isPlaying
            )
        }
        self.audioRecorderService.onPCMData = { [weak self] data in
            self?.recordingSessionStore.registerCapturedPCM(bytes: data.count)
            self?.handlePCMChunk(data)
        }
        self.audioRecorderService.onLifecycleEvent = { [weak self] event in
            self?.handleAudioSessionLifecycleEvent(event)
        }
        self.asrService.onStateChange = { [weak self] state in
            guard let self else { return }
            self.recordingSessionStore.asrState = state
            if state == .connected {
                self.cancelASRReconnect()
                if self.recordingSessionStore.pauseReason != .systemInterruption {
                    self.recordingSessionStore.infoBanner = nil
                }
                self.recordingSessionStore.errorBanner = nil
                self.settingsStore.markASRStreamSucceeded()
            }
        }
        self.asrService.onTransportEvent = { [weak self] message in
            self?.recordingSessionStore.lastASRTransportMessage = message
        }
        self.asrService.onPCMChunkSent = { [weak self] bytes in
            self?.recordingSessionStore.registerSentPCM(bytes: bytes)
        }
        self.asrService.onPartialText = { [weak self] partial in
            self?.recordingSessionStore.currentPartial = partial
        }
        self.asrService.onFinalResult = { [weak self] result in
            self?.handleFinalTranscript(result)
        }
        self.asrService.onError = { [weak self] message in
            guard let self else { return }
            let recordingMeetingID = self.recordingSessionStore.meetingID
            if self.recordingSessionStore.phase == .recording {
                if self.recordingSessionStore.isAppInBackground {
                    if let recordingMeetingID,
                       !self.recordingSessionStore.isBackgroundChunkingActive,
                       !self.recordingSessionStore.backgroundChunkFailureNeedsRepair {
                        self.enterBackgroundChunkTranscriptionIfNeeded(for: recordingMeetingID)
                    }
                } else {
                    self.recordingSessionStore.markTranscriptCoverageGap()
                    if let recordingMeetingID {
                        self.scheduleASRReconnect(for: recordingMeetingID, delay: .seconds(2))
                    }
                }
            }
            self.recordingSessionStore.infoBanner = nil
            self.recordingSessionStore.errorBanner = nil
            self.settingsStore.markASRStreamFailed(message: message)
        }
    }

    var selectedMeeting: Meeting? {
        guard let selectedMeetingID else { return nil }
        return try? repository.meeting(withID: selectedMeetingID)
    }

    var activeRecordingMeeting: Meeting? {
        guard let meetingID = recordingSessionStore.meetingID else { return nil }
        return meeting(withID: meetingID)
    }

    func logoutBlockingMessage() -> String? {
        if recordingSessionStore.phase != .idle {
            return "当前仍有录音进行中，请先结束录音。"
        }

        let pendingMeetings = ((try? repository.fetchMeetings(includeDeleted: true)) ?? [])
            .filter { $0.syncState != .synced }

        guard !pendingMeetings.isEmpty else {
            return nil
        }

        return "还有 \(pendingMeetings.count) 条未同步数据，请先同步或确认放弃。"
    }

    func resetLocalAccountData() {
        cancelAllBackgroundTasks()
        stopActiveRecordingAndDiscardArtifactIfNeeded()

        let allMeetings = ((try? repository.fetchMeetings(includeDeleted: true)) ?? [])
        for meeting in allMeetings {
            discardLocalMeetingState(for: meeting)
            removeLocalAudioIfNeeded(for: meeting)
        }

        var resetErrorMessage: String?
        do {
            try repository.deleteAllMeetings()
            try chatSessionRepository.deleteAllSessions()
        } catch {
            resetErrorMessage = error.localizedDescription
        }

        meetings = []
        selectedMeetingID = nil
        lastErrorMessage = resetErrorMessage
        enhancingMeetingIDs.removeAll()
        generatingTitleMeetingIDs.removeAll()
        streamingChatMeetingIDs.removeAll()
        transcribingMeetingIDs.removeAll()
        activeChatSessionIDs.removeAll()
        draftChatMeetingIDs.removeAll()
        fileTranscriptionStatuses.removeAll()
        fileTranscriptionPartials.removeAll()
        settingsStore.hiddenWorkspaceID = nil
        settingsStore.workspaceBootstrapState = .idle
        settingsStore.workspaceStatusMessage = "等待登录"
        settingsStore.syncStatusMessage = ""
        settingsStore.resetRemoteStatus()
        didLoad = false
        didStartBackendPreparation = false
    }

    func loadIfNeeded() {
        guard !didLoad else { return }
        didLoad = true
        recoverInterruptedFileTranscriptionsIfNeeded()
        loadMeetings()
        migrateLegacyChatSessionsIfNeeded()
        startBackendPreparationIfNeeded()
    }

    func loadMeetings() {
        isLoading = true
        defer { isLoading = false }

        do {
            meetings = try repository.fetchMeetings(matching: searchText)
            if let selectedMeetingID,
               meetings.contains(where: { $0.id == selectedMeetingID }) {
                return
            }
            selectedMeetingID = meetings.first?.id
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    @discardableResult
    func createMeeting(startingRecording: Bool = false) -> Meeting? {
        if startingRecording, recordingSessionStore.phase != .idle {
            let message = "请先结束当前录音，再开始新的会议。"
            lastErrorMessage = message
            recordingSessionStore.errorBanner = message
            return nil
        }

        do {
            let meeting = try repository.createDraftMeeting(hiddenWorkspaceID: settingsStore.hiddenWorkspaceID)
            if startingRecording {
                _ = primeRecordingSession(
                    meetingID: meeting.id,
                    inputMode: .microphone,
                    sourceAudioDisplayName: nil
                )
            }
            loadMeetings()
            selectedMeetingID = meeting.id
            return meeting
        } catch {
            lastErrorMessage = error.localizedDescription
            return nil
        }
    }

    func selectMeeting(id: String) {
        selectedMeetingID = id
    }

    func meeting(withID id: String) -> Meeting? {
        try? repository.meeting(withID: id)
    }

    func searchMeetings(matching query: String) -> [Meeting] {
        (try? repository.fetchMeetings(matching: query)) ?? []
    }

    func searchMeetingResults(matching query: String) -> [MeetingSearchResult] {
        MeetingSearchIndexBuilder.searchResults(for: meetings, query: query)
    }

    func clearLastError() {
        lastErrorMessage = nil
    }

    func updateTitle(_ title: String, for meeting: Meeting) {
        meeting.title = title
        meeting.markPending()
        persistChanges()
        scheduleMeetingSync(meetingID: meeting.id, delay: .seconds(1))
    }

    func updateNotes(_ notes: String, for meeting: Meeting) {
        meeting.userNotesPlainText = notes
        meeting.markPending()
        persistChanges()
        scheduleMeetingSync(meetingID: meeting.id, delay: .seconds(1.5))
    }

    func updateEnhancedNotes(_ notes: String, for meeting: Meeting) {
        meeting.enhancedNotes = notes
        meeting.markPending()
        persistChanges()
        scheduleMeetingSync(meetingID: meeting.id, delay: .seconds(1.5))
    }

    func noteAttachmentLimit(for meeting: Meeting) -> Int {
        max(Self.maxNoteAttachmentsPerMeeting - meeting.noteAttachmentFileNames.count, 0)
    }

    func canAddNoteAttachment(to meeting: Meeting) -> Bool {
        noteAttachmentLimit(for: meeting) > 0
    }

    func addNoteAttachment(_ image: UIImage, to meeting: Meeting) {
        guard canAddNoteAttachment(to: meeting) else {
            lastErrorMessage = AppStrings.current.noteAttachmentLimitReached(Self.maxNoteAttachmentsPerMeeting)
            return
        }

        do {
            let fileName = try MeetingNoteAttachmentStorage.saveImage(
                image,
                meetingID: meeting.id
            )
            meeting.noteAttachmentFileNames.append(fileName)
            meeting.updatedAt = .now
            persistChanges()
            scheduleNoteAttachmentTextRefresh(for: meeting)
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func removeNoteAttachment(fileName: String, from meeting: Meeting) {
        let previousText = meeting.noteAttachmentTextContext.trimmedForImageText
        cancelNoteAttachmentTextTask(for: meeting.id)
        MeetingNoteAttachmentStorage.deleteImage(meetingID: meeting.id, fileName: fileName)
        meeting.noteAttachmentFileNames.removeAll { $0 == fileName }
        meeting.updatedAt = .now

        if meeting.noteAttachmentFileNames.isEmpty {
            clearNoteAttachmentText(for: meeting)
            markMeetingPendingImageTextRefreshIfNeeded(
                meeting: meeting,
                previousText: previousText,
                newText: ""
            )
            persistChanges()
            return
        }

        persistChanges()
        scheduleNoteAttachmentTextRefresh(for: meeting)
    }

    func updateMeetingType(_ meetingType: String, for meeting: Meeting) {
        guard meeting.meetingType != meetingType else { return }

        meeting.meetingType = meetingType
        meeting.updatedAt = .now
        persistChanges()

        guard shouldAutoRefreshEnhancedNotesAfterMeetingTypeChange(for: meeting) else {
            return
        }

        let meetingID = meeting.id
        Task { @MainActor [weak self] in
            await self?.generateEnhancedNotes(for: meetingID)
        }
    }

    func updateSpeakerDisplayName(_ displayName: String, for speaker: String, in meeting: Meeting) {
        let previousSpeakers = meeting.speakers
        meeting.setDisplayName(displayName, forSpeaker: speaker)

        guard meeting.speakers != previousSpeakers else { return }

        meeting.markPending()
        persistChanges()
        scheduleMeetingSync(meetingID: meeting.id, delay: .seconds(1))
    }

    func persistChanges() {
        do {
            try repository.save()
            loadMeetings()
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func deleteMeeting(id: String) {
        guard let meeting = meeting(withID: id) else {
            return
        }

        if recordingSessionStore.meetingID == id, recordingSessionStore.phase != .idle {
            lastErrorMessage = "请先结束当前录音，再删除这条会议。"
            return
        }

        lastErrorMessage = nil
        let requiresRemoteDeletion = meeting.lastSyncedAt != nil
            || meeting.syncState == .synced
            || meeting.audioRemotePath != nil

        do {
            if !requiresRemoteDeletion {
                try deleteMeetingLocally(meeting)
                return
            }

            try stageMeetingForDeferredDeletion(meeting)
        } catch {
            lastErrorMessage = error.localizedDescription
            return
        }

        Task { @MainActor [weak self] in
            await self?.syncMeetingIfPossible(meetingID: id)
        }
    }

    func startFileTranscription(meetingID: String, sourceAudio: SourceAudioAsset) async {
        if recordingSessionStore.phase != .idle {
            lastErrorMessage = "请先结束当前录音，再开始新的文件转写。"
            return
        }

        guard let meeting = meeting(withID: meetingID) else { return }
        lastErrorMessage = nil
        fileTranscriptionStatuses[meetingID] = FileTranscriptionStatusSnapshot(
            phase: .preparing,
            errorMessage: nil
        )
        fileTranscriptionPartials[meetingID] = ""

        do {
            let importedAudio = try await AudioFileTranscriptionService.importAudioFile(
                sourceAudio,
                meetingID: meetingID
            )
            try prepareMeetingForFileTranscription(
                meeting: meeting,
                importedAudio: importedAudio,
                resetTranscript: true
            )
            beginFileTranscriptionTask(meetingID: meetingID, importedAudio: importedAudio)
        } catch {
            markFileTranscriptionFailed(meetingID: meetingID, message: error.localizedDescription)
        }
    }

    func retryFileTranscription(meetingID: String) async {
        if recordingSessionStore.phase != .idle {
            lastErrorMessage = "请先结束当前录音，再重新转写文件。"
            return
        }

        guard let meeting = meeting(withID: meetingID) else { return }
        lastErrorMessage = nil

        if meeting.speakerDiarizationState == .failed {
            meeting.speakerDiarizationState = .processing
            meeting.speakerDiarizationErrorMessage = nil
            meeting.transcriptPipelineState = .refining
            meeting.markPending()
            try? repository.save()
            loadMeetings()
            await finalizeStoppedMeeting(meetingID: meetingID)
            return
        }

        guard let audioLocalPath = meeting.audioLocalPath else {
            let message = "找不到原始音频文件，无法重新转写。"
            lastErrorMessage = message
            fileTranscriptionStatuses[meetingID] = FileTranscriptionStatusSnapshot(
                phase: nil,
                errorMessage: message,
                showsFailure: true
            )
            return
        }

        do {
            fileTranscriptionStatuses[meetingID] = FileTranscriptionStatusSnapshot(
                phase: .preparing,
                errorMessage: nil
            )
            fileTranscriptionPartials[meetingID] = ""
            let descriptor = try AudioFileTranscriptionService.describeAudioFile(
                at: URL(fileURLWithPath: audioLocalPath),
                fallbackDisplayName: meeting.sourceAudioDisplayName
            )
            try prepareMeetingForFileTranscription(
                meeting: meeting,
                importedAudio: descriptor,
                resetTranscript: true
            )
            beginFileTranscriptionTask(meetingID: meetingID, importedAudio: descriptor)
        } catch {
            markFileTranscriptionFailed(meetingID: meetingID, message: error.localizedDescription)
        }
    }

    func startRecording(meetingID: String, sourceAudio: SourceAudioAsset? = nil) async {
        let inputMode: RecordingInputMode = sourceAudio == nil ? .microphone : .fileMix
        guard primeRecordingSession(
            meetingID: meetingID,
            inputMode: inputMode,
            sourceAudioDisplayName: sourceAudio?.displayName
        ) else {
            return
        }

        guard let meeting = meeting(withID: meetingID) else {
            recordingSessionStore.reset()
            updateKeepScreenAwake()
            return
        }

        do {
            let artifact = try await audioRecorderService.startRecording(
                meetingID: meetingID,
                sourceAudio: sourceAudio
            )
            recordingSessionStore.phase = .recording
            recordingSessionStore.pauseReason = nil
            lastPublishedLiveActivityDurationSeconds = nil
            updateKeepScreenAwake()
            meeting.date = .now
            meeting.recordingMode = artifact.inputMode.meetingMode
            meeting.audioLocalPath = artifact.fileURL.path
            meeting.audioMimeType = artifact.mimeType
            meeting.audioUpdatedAt = .now
            meeting.sourceAudioLocalPath = artifact.sourceAudioLocalPath
            meeting.sourceAudioDisplayName = artifact.sourceAudioDisplayName
            meeting.sourceAudioDuration = artifact.sourceAudioDurationSeconds
            meeting.status = .recording
            meeting.markPending()
            try repository.save()
            selectedMeetingID = meetingID
            loadMeetings()
            recordingLiveActivityCoordinator.start(
                meetingID: meetingID,
                phase: .recording,
                durationSeconds: 0
            )
            Task { @MainActor [weak self] in
                await self?.startASRIfPossible(for: meetingID)
            }
        } catch {
            recordingSessionStore.errorBanner = error.localizedDescription
            recordingSessionStore.phase = .idle
            recordingSessionStore.meetingID = nil
            recordingSessionStore.asrState = .idle
            recordingLiveActivityCoordinator.end()
            updateKeepScreenAwake()
            lastErrorMessage = error.localizedDescription
        }
    }

    @discardableResult
    private func primeRecordingSession(
        meetingID: String,
        inputMode: RecordingInputMode,
        sourceAudioDisplayName: String?
    ) -> Bool {
        if let activeMeetingID = recordingSessionStore.meetingID,
           activeMeetingID != meetingID,
           recordingSessionStore.phase != .idle {
            let message = "请先结束当前录音，再开始新的会议。"
            recordingSessionStore.errorBanner = message
            lastErrorMessage = message
            return false
        }

        guard meeting(withID: meetingID) != nil else { return false }

        if recordingSessionStore.meetingID == meetingID,
           recordingSessionStore.phase == .starting,
           recordingSessionStore.inputMode == inputMode,
           recordingSessionStore.sourceAudioDisplayName == sourceAudioDisplayName {
            return true
        }

        cancelASRReconnect()
        backgroundTranscriptBackfillTask?.cancel()
        backgroundTranscriptBackfillTask = nil
        clearBackgroundShadowBuffer(keepingCapacity: false)
        shouldFlushBackgroundTranscriptTail = false
        recordingSessionStore.errorBanner = nil
        recordingSessionStore.infoBanner = nil
        recordingSessionStore.beginSession(
            inputMode: inputMode,
            sourceAudioDisplayName: sourceAudioDisplayName
        )
        recordingSessionStore.asrState = .connecting
        recordingSessionStore.meetingID = meetingID
        recordingSessionStore.phase = .starting
        updateKeepScreenAwake()
        return true
    }

    func pauseRecording() async {
        guard recordingSessionStore.phase != .stopping else { return }
        guard let meeting = currentRecordingMeeting() else { return }

        do {
            cancelASRReconnect()
            backgroundTranscriptBackfillTask?.cancel()
            backgroundTranscriptBackfillTask = nil
            shouldFlushBackgroundTranscriptTail = false
            try audioRecorderService.pauseRecording()
            await asrService.stopStreaming()
            recordingSessionStore.phase = .paused
            recordingSessionStore.pauseReason = .user
            recordingSessionStore.currentPartial = ""
            recordingSessionStore.infoBanner = nil
            recordingSessionStore.clearBackgroundChunkingState()
            recordingSessionStore.clearBackgroundTranscriptGap()
            clearBackgroundShadowBuffer(keepingCapacity: false)
            recordingLiveActivityCoordinator.update(
                phase: .paused,
                durationSeconds: recordingSessionStore.durationSeconds
            )
            updateKeepScreenAwake()
            meeting.status = .paused
            meeting.markPending()
            try repository.save()
            loadMeetings()
        } catch {
            recordingSessionStore.errorBanner = error.localizedDescription
        }
    }

    func resumeRecording() async {
        guard recordingSessionStore.phase != .stopping else { return }
        guard let meeting = currentRecordingMeeting() else { return }

        do {
            try audioRecorderService.resumeRecording()
            recordingSessionStore.phase = .recording
            recordingSessionStore.pauseReason = nil
            recordingSessionStore.asrState = .connecting
            recordingSessionStore.infoBanner = nil
            recordingSessionStore.deactivateBackgroundChunking()
            clearBackgroundShadowBuffer(keepingCapacity: true)
            recordingLiveActivityCoordinator.update(
                phase: .recording,
                durationSeconds: recordingSessionStore.durationSeconds
            )
            updateKeepScreenAwake()
            meeting.status = .recording
            meeting.markPending()
            try repository.save()
            loadMeetings()
            await startASRIfPossible(for: meeting.id)
        } catch {
            recordingSessionStore.errorBanner = error.localizedDescription
        }
    }

    func stopRecording() async {
        guard recordingSessionStore.phase != .stopping else { return }
        guard let meeting = currentRecordingMeeting() else { return }

        do {
            cancelASRReconnect()
            recordingSessionStore.phase = .stopping
            recordingSessionStore.infoBanner = nil
            recordingLiveActivityCoordinator.end()
            updateKeepScreenAwake()
            await asrService.stopStreaming()
            let artifact = try audioRecorderService.stopRecording()
            await finishStoppedRecording(meetingID: meeting.id, artifact: artifact)
        } catch {
            recordingSessionStore.errorBanner = error.localizedDescription
        }
    }

    func handleScenePhaseChange(_ phase: ScenePhase) {
        let isBackground = phase == .background
        recordingSessionStore.isAppInBackground = isBackground

        if phase == .active,
           didStartBackendPreparation,
           (!settingsStore.apiReachable || settingsStore.workspaceBootstrapState != .success) {
            scheduleBackendPreparationIfNeeded(retryDelays: [.zero, .seconds(2)])
        }

        guard let meetingID = recordingSessionStore.meetingID else {
            recordingSessionStore.infoBanner = nil
            return
        }

        switch phase {
        case .background:
            if recordingSessionStore.phase == .recording {
                recordingSessionStore.currentPartial = ""
                recordingSessionStore.infoBanner = nil
                beginBackgroundShadowBuffering()
            }
        case .active:
            if recordingSessionStore.phase == .recording {
                switch audioRecorderService.reconcileForegroundRecording() {
                case .healthy, .recovered:
                    Task { @MainActor [weak self] in
                        await self?.restoreForegroundLiveTranscriptionIfNeeded(for: meetingID)
                    }
                case let .needsUserResume(message):
                    Task { @MainActor [weak self] in
                        await self?.pauseRecordingAfterForegroundInterruption(message: message)
                    }
                }
            } else if recordingSessionStore.pauseReason != .systemInterruption {
                recordingSessionStore.infoBanner = nil
            }
        case .inactive:
            break
        @unknown default:
            break
        }
    }

    func checkBackendHealth(force: Bool = true) async {
        if !needsFreshHealthCheck(force: force) {
            return
        }

        if settingsStore.isCheckingHealth {
            while settingsStore.isCheckingHealth {
                try? await Task.sleep(for: .milliseconds(120))
            }
            return
        }

        settingsStore.isCheckingHealth = true
        defer { settingsStore.isCheckingHealth = false }

        var backendError: Error?
        var asrError: Error?
        var llmError: Error?
        var didReachBackend = false
        var backendHealth: RemoteBackendHealth?

        do {
            backendHealth = try await apiClient.fetchBackendHealth()
            settingsStore.markBackendReachable(
                message: backendStatusMessage(from: backendHealth),
                checkedAt: backendHealth?.checkedAt
            )
            didReachBackend = true
        } catch {
            backendError = error
        }

        if let asrStatus = backendHealth?.asr {
            settingsStore.updateASRStatus(asrStatus)
        } else {
            do {
                let asrStatus = try await apiClient.fetchASRStatus()
                if !didReachBackend {
                    settingsStore.markBackendReachable(
                        checkedAt: asrStatus.checkedAt
                    )
                }
                settingsStore.updateASRStatus(asrStatus)
                didReachBackend = true
            } catch {
                asrError = error
            }
        }

        if let llmStatus = backendHealth?.llm {
            settingsStore.updateLLMStatus(llmStatus)
        } else {
            do {
                let llmStatus = try await apiClient.fetchLLMStatus()
                if !didReachBackend {
                    settingsStore.markBackendReachable(
                        checkedAt: llmStatus.checkedAt
                    )
                }
                settingsStore.updateLLMStatus(llmStatus)
                didReachBackend = true
            } catch {
                llmError = error
            }
        }

        guard didReachBackend else {
            settingsStore.markBackendUnreachable(
                message: backendError?.localizedDescription
                    ?? asrError?.localizedDescription
                    ?? llmError?.localizedDescription
                    ?? "\(AppEnvironment.cloudName) 暂时不可用。"
            )
            return
        }

        if backendHealth?.asr == nil, let asrError {
            settingsStore.markASRStreamFailed(message: asrError.localizedDescription)
        }

        if backendHealth?.llm == nil, let llmError {
            settingsStore.markLLMRequestFailed(message: llmError.localizedDescription)
        }
    }

    @discardableResult
    func bootstrapHiddenWorkspace(force: Bool = false, surfaceBlockingError: Bool = true) async -> String? {
        if !force,
           let hiddenWorkspaceID = settingsStore.hiddenWorkspaceID,
           settingsStore.workspaceBootstrapState == .success {
            return hiddenWorkspaceID
        }

        do {
            return try await workspaceBootstrapService.bootstrapHiddenWorkspace()
        } catch {
            settingsStore.workspaceBootstrapState = .failed
            settingsStore.workspaceStatusMessage = error.localizedDescription
            if surfaceBlockingError {
                lastErrorMessage = error.localizedDescription
            }
            return nil
        }
    }

    func syncAllMeetings() async {
        await appActivityCoordinator.performExpiringActivity(named: "sync-all-meetings") { [weak self] in
            guard let self else { return }
            guard !settingsStore.isSyncing else {
                return
            }

            settingsStore.isSyncing = true
            defer { settingsStore.isSyncing = false }

            guard await ensureBackendReachable(force: true) else {
                settingsStore.syncStatusMessage = settingsStore.blockingMessage(for: .sync) ?? "Backend unavailable."
                return
            }

            guard await bootstrapHiddenWorkspace(force: false, surfaceBlockingError: false) != nil else {
                settingsStore.syncStatusMessage = "隐藏工作区初始化失败。"
                return
            }

            let batchResult = await meetingSyncService.syncPendingMeetings()

            do {
                let refreshedCount = try await meetingSyncService.refreshRemoteMeetings()
                loadMeetings()
                settingsStore.syncStatusMessage = "已推送 \(batchResult.syncedCount) 条，失败 \(batchResult.failedCount) 条，刷新 \(refreshedCount) 条。"
            } catch {
                recordBackgroundSyncIssue(
                    detail: error.localizedDescription,
                    summary: "推送完成，但刷新远端失败。"
                )
            }
        }
    }

    func generateEnhancedNotes(for meetingID: String) async {
        guard let meeting = meeting(withID: meetingID) else { return }
        guard !enhancingMeetingIDs.contains(meetingID) else { return }
        guard await ensureBackendReachable(force: false) else {
            lastErrorMessage = "\(AppEnvironment.cloudName) 暂时不可用。"
            return
        }

        let transcriptFingerprint = meeting.transcriptFingerprint

        enhancingMeetingIDs.insert(meetingID)
        defer { enhancingMeetingIDs.remove(meetingID) }

        do {
            let response = try await apiClient.enhanceNotes(MeetingPayloadMapper.makeEnhancePayload(from: meeting))
            meeting.enhancedNotes = normalizeGeneratedNotes(response.content)
            meeting.aiNotesFreshnessState = .fresh
            meeting.lastAINotesTranscriptFingerprint = transcriptFingerprint
            meeting.markPending()
            try repository.save()
            settingsStore.markLLMRequestSucceeded(provider: response.provider)
            loadMeetings()
            await syncMeetingIfPossible(meetingID: meetingID)
        } catch {
            lastErrorMessage = error.localizedDescription
            settingsStore.markLLMRequestFailed(message: error.localizedDescription)
        }
    }

    func sendChatMessage(question: String, for meetingID: String) async -> Bool {
        let trimmedQuestion = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuestion.isEmpty else { return false }
        return await enqueueMeetingChatTask(for: meetingID) { [weak self] in
            guard let self else { return false }
            return await self.performSendChatMessage(
                question: trimmedQuestion,
                for: meetingID
            )
        }
    }

    func regenerateLastChatResponse(for meetingID: String) async -> Bool {
        await enqueueMeetingChatTask(for: meetingID) { [weak self] in
            guard let self else { return false }
            return await self.performRegenerateLastChatResponse(for: meetingID)
        }
    }

    func isEnhancing(meetingID: String) -> Bool {
        enhancingMeetingIDs.contains(meetingID)
    }

    func isGeneratingTitle(meetingID: String) -> Bool {
        generatingTitleMeetingIDs.contains(meetingID)
    }

    func isStreamingChat(meetingID: String) -> Bool {
        streamingChatMeetingIDs.contains(meetingID)
    }

    func canRegenerateLastChatResponse(for meetingID: String) -> Bool {
        guard !streamingChatMeetingIDs.contains(meetingID),
              let session = activeChatSession(for: meetingID) else {
            return false
        }

        return session.orderedMessages.contains(where: { $0.role == "user" })
    }

    func prepareChatSessions(for meetingID: String) {
        guard let meeting = meeting(withID: meetingID) else { return }

        do {
            try chatSessionRepository.migrateLegacyMeetingChatsIfNeeded(for: meeting)
        } catch {
            lastErrorMessage = error.localizedDescription
        }

        guard !draftChatMeetingIDs.contains(meetingID) else { return }
        if activeChatSessionIDs[meetingID] == nil {
            activeChatSessionIDs[meetingID] = meeting.orderedChatSessions.first?.id
        }
    }

    func chatSessions(for meetingID: String) -> [ChatSession] {
        guard let meeting = meeting(withID: meetingID) else { return [] }
        return meeting.orderedChatSessions
    }

    func activeChatSession(for meetingID: String) -> ChatSession? {
        guard !draftChatMeetingIDs.contains(meetingID) else { return nil }
        guard let meeting = meeting(withID: meetingID) else { return nil }
        if let activeID = activeChatSessionIDs[meetingID] {
            return meeting.chatSessions.first(where: { $0.id == activeID })
        }
        return meeting.orderedChatSessions.first
    }

    func chatMessages(for meetingID: String) -> [ChatMessage] {
        activeChatSession(for: meetingID)?.orderedMessages ?? []
    }

    func startNewChatDraft(for meetingID: String) {
        prepareChatSessions(for: meetingID)
        lastErrorMessage = nil
        draftChatMeetingIDs.insert(meetingID)
        activeChatSessionIDs.removeValue(forKey: meetingID)
    }

    func activateChatSession(_ sessionID: String, for meetingID: String) {
        prepareChatSessions(for: meetingID)
        lastErrorMessage = nil
        draftChatMeetingIDs.remove(meetingID)
        activeChatSessionIDs[meetingID] = sessionID
    }

    func deleteChatSession(_ sessionID: String, for meetingID: String) {
        guard !streamingChatMeetingIDs.contains(meetingID) else { return }
        guard let meeting = meeting(withID: meetingID),
              let session = meeting.chatSessions.first(where: { $0.id == sessionID }) else {
            return
        }

        do {
            let remainingSessions = meeting.orderedChatSessions.filter { $0.id != sessionID }
            try chatSessionRepository.delete(session)
            lastErrorMessage = nil
            if activeChatSessionIDs[meetingID] == sessionID {
                activeChatSessionIDs[meetingID] = remainingSessions.first?.id
                if remainingSessions.isEmpty {
                    draftChatMeetingIDs.insert(meetingID)
                } else {
                    draftChatMeetingIDs.remove(meetingID)
                }
            }
            loadMeetings()
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func isFileTranscribing(meetingID: String) -> Bool {
        if transcribingMeetingIDs.contains(meetingID) {
            return true
        }

        guard let meeting = meeting(withID: meetingID) else {
            return false
        }

        switch meeting.transcriptPipelineState {
        case .initializing, .refining:
            return true
        case .idle, .ready, .failed:
            return false
        }
    }

    func fileTranscriptionStatus(meetingID: String) -> FileTranscriptionStatusSnapshot? {
        if let status = fileTranscriptionStatuses[meetingID] {
            return status
        }

        guard let meeting = meeting(withID: meetingID) else {
            return nil
        }

        switch meeting.transcriptPipelineState {
        case .idle, .ready:
            return nil
        case .initializing, .refining:
            return FileTranscriptionStatusSnapshot(
                phase: .finalizing,
                errorMessage: nil
            )
        case .failed:
            return FileTranscriptionStatusSnapshot(
                phase: nil,
                errorMessage: UserVisibleMediaErrorFormatter.transcriptionFailureDetail(
                    from: meeting.speakerDiarizationErrorMessage
                ),
                showsFailure: true
            )
        }
    }

    func fileTranscriptionPartial(meetingID: String) -> String {
        fileTranscriptionPartials[meetingID] ?? ""
    }

    func prepareAI(force: Bool = false) async -> Bool {
        await ensureBackendReachable(force: force)
    }

    func toggleSourceAudioPlayback() {
        do {
            try audioRecorderService.toggleSourceAudioPlayback()
        } catch {
            recordingSessionStore.errorBanner = error.localizedDescription
        }
    }

    func finishStoppedRecording(meetingID: String, artifact: LocalAudioArtifact) async {
        guard let meeting = meeting(withID: meetingID) else {
            lastPublishedLiveActivityDurationSeconds = nil
            recordingLiveActivityCoordinator.end()
            recordingSessionStore.reset()
            updateKeepScreenAwake()
            loadMeetings()
            return
        }

        lastErrorMessage = nil
        await finalizeBackgroundTranscriptBeforeStop(meetingID: meetingID)
        let needsTranscriptRepair = recordingSessionStore.needsTranscriptRepairAfterStop
            || recordingSessionStore.backgroundChunkFailureNeedsRepair
            || recordingSessionStore.hasBackgroundTranscriptGap
            || recordingSessionStore.isBackfillingBackgroundTranscript
            || (recordingSessionStore.isBackgroundChunkingActive && !backgroundTranscriptPCMBuffer.isEmpty)
            || backgroundTranscriptBackfillTask != nil
        fileTranscriptionTasks[meetingID]?.cancel()
        fileTranscriptionTasks[meetingID] = nil
        transcribingMeetingIDs.remove(meetingID)
        fileTranscriptionStatuses.removeValue(forKey: meetingID)
        fileTranscriptionPartials.removeValue(forKey: meetingID)
        clearBackgroundShadowBuffer(keepingCapacity: false)
        shouldFlushBackgroundTranscriptTail = false

        meeting.status = .ended
        meeting.audioLocalPath = artifact.fileURL.path
        meeting.audioMimeType = artifact.mimeType
        meeting.audioDuration = artifact.durationSeconds
        meeting.audioUpdatedAt = .now
        meeting.durationSeconds = max(meeting.durationSeconds, artifact.durationSeconds)
        meeting.transcriptPipelineState = needsTranscriptRepair ? .refining : .ready
        meeting.speakerDiarizationState = needsTranscriptRepair ? .processing : .idle
        meeting.speakerDiarizationErrorMessage = nil
        updateTranscriptNotesFreshnessIfNeeded(for: meeting)
        meeting.markPending()

        do {
            try repository.save()
        } catch {
            recordingSessionStore.errorBanner = error.localizedDescription
            lastErrorMessage = error.localizedDescription
            recordingSessionStore.reset()
            updateKeepScreenAwake()
            loadMeetings()
            return
        }

        recordingSessionStore.reset()
        lastPublishedLiveActivityDurationSeconds = nil
        updateKeepScreenAwake()
        loadMeetings()

        await appActivityCoordinator.performExpiringActivity(named: "finish-meeting-\(meetingID)") { [weak self] in
            guard let self else { return }

            if needsTranscriptRepair {
                await self.repairStoppedRecordingTranscript(meetingID: meetingID, artifact: artifact)
                return
            }

            await self.finalizeStoppedMeeting(meetingID: meetingID)
        }
    }

    private func prepareMeetingForFileTranscription(
        meeting: Meeting,
        importedAudio: ImportedAudioFileDescriptor,
        resetTranscript: Bool
    ) throws {
        if resetTranscript {
            repository.replaceSegments(for: meeting, with: [])
        }

        meeting.date = .now
        meeting.status = .transcribing
        meeting.recordingMode = .microphone
        meeting.transcriptPipelineState = .initializing
        meeting.speakerDiarizationState = .idle
        meeting.speakerDiarizationErrorMessage = nil
        meeting.audioLocalPath = importedAudio.fileURL.path
        meeting.audioMimeType = importedAudio.mimeType
        meeting.audioDuration = importedAudio.durationSeconds
        meeting.audioUpdatedAt = .now
        meeting.durationSeconds = importedAudio.durationSeconds
        meeting.sourceAudioLocalPath = nil
        meeting.sourceAudioDisplayName = importedAudio.displayName
        meeting.sourceAudioDuration = importedAudio.durationSeconds
        meeting.markPending()
        try repository.save()

        selectedMeetingID = meeting.id
        fileTranscriptionStatuses[meeting.id] = FileTranscriptionStatusSnapshot(
            phase: .preparing,
            errorMessage: nil
        )
        fileTranscriptionPartials[meeting.id] = ""
        loadMeetings()
    }

    private func beginFileTranscriptionTask(meetingID: String, importedAudio: ImportedAudioFileDescriptor) {
        fileTranscriptionTasks[meetingID]?.cancel()

        let task = Task<Void, Never> { @MainActor [weak self] in
            guard let self else { return }
            await self.appActivityCoordinator.performExpiringActivity(named: "transcribe-file-\(meetingID)") { [weak self] in
                guard let self else { return }
                await self.runFileTranscription(meetingID: meetingID, importedAudio: importedAudio)
            }
        }

        fileTranscriptionTasks[meetingID] = task
    }

    private func runFileTranscription(meetingID: String, importedAudio: ImportedAudioFileDescriptor) async {
        transcribingMeetingIDs.insert(meetingID)
        fileTranscriptionStatuses[meetingID] = FileTranscriptionStatusSnapshot(
            phase: .preparing,
            errorMessage: nil
        )
        fileTranscriptionPartials[meetingID] = ""
        loadMeetings()

        defer {
            transcribingMeetingIDs.remove(meetingID)
            fileTranscriptionTasks[meetingID] = nil
            loadMeetings()
        }

        do {
            await checkBackendHealth(force: false)

            guard settingsStore.apiReachable else {
                throw APIClientError.requestFailed(
                    settingsStore.blockingMessage(for: .backend) ?? "\(AppEnvironment.cloudName) 暂时不可用。"
                )
            }

            let existingWorkspaceID = meeting(withID: meetingID)?.hiddenWorkspaceId ?? settingsStore.hiddenWorkspaceID
            let workspaceID: String?
            if let existingWorkspaceID {
                workspaceID = existingWorkspaceID
            } else {
                workspaceID = await bootstrapHiddenWorkspace(force: false, surfaceBlockingError: false)
            }

            if let meeting = meeting(withID: meetingID), meeting.hiddenWorkspaceId != workspaceID {
                meeting.hiddenWorkspaceId = workspaceID
                meeting.markPending()
                try repository.save()
            }

            try await audioFileTranscriptionService.transcribe(
                fileURL: importedAudio.fileURL,
                workspaceID: workspaceID,
                onPhaseChange: { [weak self] phase in
                    guard let self else { return }
                    self.fileTranscriptionStatuses[meetingID] = FileTranscriptionStatusSnapshot(
                        phase: phase,
                        errorMessage: nil
                    )
                },
                onPartialText: { [weak self] partial in
                    guard let self else { return }
                    self.fileTranscriptionPartials[meetingID] = partial
                },
                onFinalResult: { [weak self] result in
                    self?.appendImportedAudioTranscript(result, meetingID: meetingID)
                }
            )

            guard let meeting = meeting(withID: meetingID) else { return }

            meeting.status = .ended
            meeting.transcriptPipelineState = .ready
            meeting.audioDuration = importedAudio.durationSeconds
            meeting.durationSeconds = importedAudio.durationSeconds
            meeting.audioUpdatedAt = .now
            updateTranscriptNotesFreshnessIfNeeded(for: meeting)
            meeting.markPending()
            try repository.save()
            settingsStore.markASRStreamSucceeded()
            fileTranscriptionStatuses[meetingID] = FileTranscriptionStatusSnapshot(
                phase: .finalizing,
                errorMessage: nil
            )
            fileTranscriptionPartials[meetingID] = ""
            await finalizeStoppedMeeting(meetingID: meetingID)
            fileTranscriptionStatuses.removeValue(forKey: meetingID)
            fileTranscriptionPartials.removeValue(forKey: meetingID)
        } catch is CancellationError {
            return
        } catch {
            markFileTranscriptionFailed(meetingID: meetingID, message: error.localizedDescription)
            settingsStore.markASRStreamFailed(message: error.localizedDescription)
        }
    }

    private func repairStoppedRecordingTranscript(meetingID: String, artifact: LocalAudioArtifact) async {
        transcribingMeetingIDs.insert(meetingID)
        fileTranscriptionStatuses[meetingID] = FileTranscriptionStatusSnapshot(
            phase: .preparing,
            errorMessage: nil
        )
        fileTranscriptionPartials[meetingID] = ""
        loadMeetings()

        defer {
            transcribingMeetingIDs.remove(meetingID)
            loadMeetings()
        }

        do {
            await checkBackendHealth(force: false)

            guard settingsStore.apiReachable else {
                throw APIClientError.requestFailed(
                    settingsStore.blockingMessage(for: .backend) ?? "\(AppEnvironment.cloudName) 暂时不可用。"
                )
            }

            let existingWorkspaceID = meeting(withID: meetingID)?.hiddenWorkspaceId ?? settingsStore.hiddenWorkspaceID
            let workspaceID: String?
            if let existingWorkspaceID {
                workspaceID = existingWorkspaceID
            } else {
                workspaceID = await bootstrapHiddenWorkspace(force: false, surfaceBlockingError: false)
            }

            if let meeting = meeting(withID: meetingID), meeting.hiddenWorkspaceId != workspaceID {
                meeting.hiddenWorkspaceId = workspaceID
                meeting.markPending()
                try repository.save()
            }

            var repairedResults: [ASRFinalResult] = []
            try await audioFileTranscriptionService.transcribe(
                fileURL: artifact.fileURL,
                workspaceID: workspaceID,
                onPhaseChange: { [weak self] phase in
                    guard let self else { return }
                    self.fileTranscriptionStatuses[meetingID] = FileTranscriptionStatusSnapshot(
                        phase: phase,
                        errorMessage: nil
                    )
                },
                onPartialText: { [weak self] partial in
                    guard let self else { return }
                    self.fileTranscriptionPartials[meetingID] = partial
                },
                onFinalResult: { result in
                    repairedResults.append(result)
                }
            )

            guard let meeting = meeting(withID: meetingID) else { return }
            let replacementSegments = makeTranscriptSegments(
                from: repairedResults,
                speaker: meeting.recordingMode == .fileMix ? "混合音频" : "麦克风"
            )
            if replacementSegments.isEmpty, !meeting.orderedSegments.isEmpty {
                throw APIClientError.requestFailed("补转写未返回任何结果。")
            }

            repository.replaceSegments(for: meeting, with: replacementSegments)
            meeting.status = .ended
            meeting.transcriptPipelineState = .refining
            meeting.audioLocalPath = artifact.fileURL.path
            meeting.audioMimeType = artifact.mimeType
            meeting.audioDuration = artifact.durationSeconds
            meeting.audioUpdatedAt = .now
            meeting.durationSeconds = max(meeting.durationSeconds, artifact.durationSeconds)
            meeting.markPending()
            try repository.save()
            settingsStore.markASRStreamSucceeded()
            fileTranscriptionStatuses[meetingID] = FileTranscriptionStatusSnapshot(
                phase: .finalizing,
                errorMessage: nil
            )
            fileTranscriptionPartials[meetingID] = ""
            updateTranscriptNotesFreshnessIfNeeded(for: meeting)
            await finalizeStoppedMeeting(meetingID: meetingID)
            fileTranscriptionStatuses.removeValue(forKey: meetingID)
            fileTranscriptionPartials.removeValue(forKey: meetingID)
        } catch is CancellationError {
            return
        } catch {
            markStoppedRecordingRepairPendingCloudFinalization(
                meetingID: meetingID,
                message: error.localizedDescription
            )
            settingsStore.markASRStreamFailed(message: error.localizedDescription)
        }
    }

    private func appendImportedAudioTranscript(_ result: ASRFinalResult, meetingID: String) {
        guard let meeting = meeting(withID: meetingID) else { return }
        fileTranscriptionPartials[meetingID] = ""
        appendTranscriptSegment(result, to: meeting, speaker: "音频文件")
    }

    private func markFileTranscriptionFailed(meetingID: String, message: String) {
        if let meeting = meeting(withID: meetingID) {
            meeting.status = .transcriptionFailed
            meeting.transcriptPipelineState = .failed
            meeting.speakerDiarizationErrorMessage = message
            meeting.audioUpdatedAt = .now
            meeting.markPending()
            try? repository.save()
        }

        fileTranscriptionStatuses[meetingID] = FileTranscriptionStatusSnapshot(
            phase: nil,
            errorMessage: UserVisibleMediaErrorFormatter.transcriptionFailureDetail(from: message),
            showsFailure: true
        )
        fileTranscriptionPartials[meetingID] = ""
        lastErrorMessage = message
        loadMeetings()
    }

    private func markStoppedRecordingRepairPendingCloudFinalization(meetingID: String, message: String) {
        if let meeting = meeting(withID: meetingID) {
            meeting.status = .ended
            meeting.transcriptPipelineState = .refining
            meeting.speakerDiarizationState = .processing
            meeting.speakerDiarizationErrorMessage = message
            meeting.audioUpdatedAt = .now
            meeting.markPending()
            try? repository.save()
        }

        fileTranscriptionStatuses.removeValue(forKey: meetingID)
        fileTranscriptionPartials[meetingID] = ""
        lastErrorMessage = message
        loadMeetings()
    }

    private func recoverInterruptedFileTranscriptionsIfNeeded() {
        let interruptedMeetings = (try? repository.fetchMeetings())?.filter { $0.status == .transcribing } ?? []
        guard !interruptedMeetings.isEmpty else { return }

        for meeting in interruptedMeetings {
            if meeting.speakerDiarizationState == .processing, meeting.audioLocalPath?.isEmpty == false {
                meeting.status = .ended
                meeting.transcriptPipelineState = .refining
                meeting.markPending()
                fileTranscriptionStatuses.removeValue(forKey: meeting.id)
                fileTranscriptionPartials[meeting.id] = ""
            } else {
                meeting.status = .transcriptionFailed
                meeting.transcriptPipelineState = .failed
                meeting.markPending()
                fileTranscriptionStatuses[meeting.id] = FileTranscriptionStatusSnapshot(
                    phase: nil,
                    errorMessage: AppStrings.current.fileTranscriptionInterrupted,
                    showsFailure: true
                )
                fileTranscriptionPartials[meeting.id] = ""
            }
        }

        try? repository.save()
    }

    private func currentRecordingMeeting() -> Meeting? {
        guard let meetingID = recordingSessionStore.meetingID else { return nil }
        return meeting(withID: meetingID)
    }

    private func handleAudioSessionLifecycleEvent(_ event: AudioSessionLifecycleEvent) {
        guard recordingSessionStore.phase == .recording else { return }

        switch event {
        case .interruptionBegan, .mediaServicesWereLost:
            recordingSessionStore.currentPartial = ""
            if !recordingSessionStore.isAppInBackground {
                recordingSessionStore.markTranscriptCoverageGap()
            }
        case let .interruptionEnded(shouldResume, _):
            if !shouldResume, !recordingSessionStore.isAppInBackground {
                recordingSessionStore.markTranscriptCoverageGap()
            }
        case .routeChanged, .mediaServicesWereReset:
            if !recordingSessionStore.isAppInBackground {
                recordingSessionStore.markTranscriptCoverageGap()
            }
        }
    }

    private func pauseRecordingAfterForegroundInterruption(message: String) async {
        cancelASRReconnect()
        backgroundTranscriptBackfillTask?.cancel()
        backgroundTranscriptBackfillTask = nil
        shouldFlushBackgroundTranscriptTail = false
        await asrService.stopStreaming()
        recordingSessionStore.currentPartial = ""
        recordingSessionStore.asrState = .idle
        recordingSessionStore.errorBanner = nil
        recordingSessionStore.infoBanner = message
        recordingSessionStore.phase = .paused
        recordingSessionStore.pauseReason = .systemInterruption
        recordingSessionStore.clearBackgroundChunkingState()
        recordingSessionStore.clearBackgroundTranscriptGap()
        clearBackgroundShadowBuffer(keepingCapacity: false)
        recordingLiveActivityCoordinator.update(
            phase: .paused,
            durationSeconds: recordingSessionStore.durationSeconds
        )
        updateKeepScreenAwake()

        guard let meeting = currentRecordingMeeting() else { return }
        meeting.status = .paused
        meeting.markPending()
        try? repository.save()
        loadMeetings()
    }

    private func currentRecordingDurationMilliseconds() -> Double {
        let durationSeconds = max(
            recordingSessionStore.durationSeconds,
            audioRecorderService.currentRecordingDurationSeconds()
        )
        return Double(max(durationSeconds, 0)) * 1_000
    }

    private func beginBackgroundShadowBuffering() {
        clearBackgroundShadowBuffer(keepingCapacity: true)
        backgroundShadowBufferStartTimeMS = currentRecordingDurationMilliseconds()
        recordingSessionStore.deactivateBackgroundChunking()
    }

    private func clearBackgroundShadowBuffer(keepingCapacity: Bool) {
        backgroundTranscriptPCMBuffer.removeAll(keepingCapacity: keepingCapacity)
        backgroundShadowBufferStartTimeMS = nil
        recordingSessionStore.markBackgroundChunkBufferDuration(0)
    }

    private func trimBackgroundShadowBufferIfNeeded() {
        let maxByteCount = backgroundPCMByteCount(forDurationMS: Self.backgroundShadowBufferMaxDurationMS)
        guard maxByteCount > 0, backgroundTranscriptPCMBuffer.count > maxByteCount else { return }

        let overflowByteCount = backgroundTranscriptPCMBuffer.count - maxByteCount
        backgroundTranscriptPCMBuffer.removeFirst(overflowByteCount)

        let overflowDurationMS = backgroundChunkDurationMS(forPCMByteCount: overflowByteCount)
        if let startTimeMS = backgroundShadowBufferStartTimeMS {
            backgroundShadowBufferStartTimeMS = startTimeMS + overflowDurationMS
        }

        if recordingSessionStore.isBackgroundChunkingActive {
            recordingSessionStore.backgroundChunkStartTimeMS = backgroundShadowBufferStartTimeMS
            recordingSessionStore.markBackgroundChunkBufferDuration(
                backgroundChunkDurationMS(forPCMByteCount: backgroundTranscriptPCMBuffer.count)
            )
            recordingSessionStore.markTranscriptCoverageGap()
        }
    }

    private func trimBackgroundShadowBuffer(through confirmedEndTimeMS: Double) {
        guard let startTimeMS = backgroundShadowBufferStartTimeMS,
              !backgroundTranscriptPCMBuffer.isEmpty else {
            return
        }

        let coveredDurationMS = confirmedEndTimeMS - startTimeMS
        guard coveredDurationMS > 0 else { return }

        let trimByteCount = min(
            backgroundPCMByteCount(forDurationMS: coveredDurationMS),
            backgroundTranscriptPCMBuffer.count
        )
        guard trimByteCount > 0 else { return }

        backgroundTranscriptPCMBuffer.removeFirst(trimByteCount)
        let trimmedDurationMS = backgroundChunkDurationMS(forPCMByteCount: trimByteCount)
        backgroundShadowBufferStartTimeMS = startTimeMS + trimmedDurationMS

        if recordingSessionStore.isBackgroundChunkingActive {
            recordingSessionStore.backgroundChunkStartTimeMS = backgroundShadowBufferStartTimeMS
            recordingSessionStore.markBackgroundChunkBufferDuration(
                backgroundChunkDurationMS(forPCMByteCount: backgroundTranscriptPCMBuffer.count)
            )
        }
    }

    private func enterBackgroundChunkTranscriptionIfNeeded(for meetingID: String) {
        guard recordingSessionStore.meetingID == meetingID,
              recordingSessionStore.phase == .recording,
              recordingSessionStore.isAppInBackground,
              !recordingSessionStore.backgroundChunkFailureNeedsRepair else {
            return
        }

        if !recordingSessionStore.isBackgroundChunkingActive {
            let startTimeMS = backgroundShadowBufferStartTimeMS ?? currentRecordingDurationMilliseconds()
            recordingSessionStore.beginBackgroundChunking(at: startTimeMS)
            recordingSessionStore.markBackgroundChunkBufferDuration(
                backgroundChunkDurationMS(forPCMByteCount: backgroundTranscriptPCMBuffer.count)
            )
        }

        recordingSessionStore.currentPartial = ""
        recordingSessionStore.infoBanner = nil
    }

    private func restoreForegroundLiveTranscriptionIfNeeded(for meetingID: String) async {
        guard recordingSessionStore.meetingID == meetingID,
              recordingSessionStore.phase == .recording else {
            return
        }

        let didFallbackInBackground = recordingSessionStore.isBackgroundChunkingActive
            || recordingSessionStore.backgroundChunkFailureNeedsRepair

        if recordingSessionStore.isBackgroundChunkingActive {
            shouldFlushBackgroundTranscriptTail = true
            scheduleBackgroundChunkTranscriptionIfNeeded(for: meetingID, forceFlushTail: true)
            await waitForBackgroundChunkTranscriptionToSettle()
        }

        shouldFlushBackgroundTranscriptTail = false
        recordingSessionStore.deactivateBackgroundChunking()

        if didFallbackInBackground || [.idle, .degraded, .disconnected].contains(recordingSessionStore.asrState) {
            clearBackgroundShadowBuffer(keepingCapacity: true)
            await startASRIfPossible(for: meetingID)
            return
        }

        clearBackgroundShadowBuffer(keepingCapacity: true)
    }

    private func finalizeBackgroundTranscriptBeforeStop(meetingID: String) async {
        guard recordingSessionStore.backgroundTranscriptionStatus != .failedNeedsRepair else {
            return
        }

        guard recordingSessionStore.isBackgroundChunkingActive else {
            return
        }

        shouldFlushBackgroundTranscriptTail = true
        scheduleBackgroundChunkTranscriptionIfNeeded(for: meetingID, forceFlushTail: true)
        await waitForBackgroundChunkTranscriptionToSettle()
    }

    private func waitForBackgroundChunkTranscriptionToSettle(timeoutSeconds: TimeInterval = 15) async {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while backgroundTranscriptBackfillTask != nil {
            if Date() >= deadline {
                recordingSessionStore.markBackgroundChunkFailureNeedsRepair()
                backgroundTranscriptBackfillTask?.cancel()
                backgroundTranscriptBackfillTask = nil
                return
            }
            try? await Task.sleep(for: .milliseconds(50))
        }
    }

    private func scheduleBackgroundChunkTranscriptionIfNeeded(for meetingID: String, forceFlushTail: Bool = false) {
        if forceFlushTail {
            shouldFlushBackgroundTranscriptTail = true
        }

        guard recordingSessionStore.meetingID == meetingID,
              recordingSessionStore.isBackgroundChunkingActive,
              !recordingSessionStore.backgroundChunkFailureNeedsRepair,
              backgroundTranscriptBackfillTask == nil else {
            return
        }

        backgroundTranscriptBackfillTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.backgroundTranscriptBackfillTask = nil }
            await self.performBackgroundChunkTranscription(meetingID: meetingID)
        }
    }

    private func performBackgroundChunkTranscription(meetingID: String) async {
        while !Task.isCancelled {
            let forceFlushTail = shouldFlushBackgroundTranscriptTail
            guard let chunk = dequeueBackgroundTranscriptChunk(forceFlushTail: forceFlushTail) else {
                if recordingSessionStore.isBackgroundChunkingActive {
                    recordingSessionStore.markBackgroundChunkReadyForMore()
                }
                if forceFlushTail {
                    shouldFlushBackgroundTranscriptTail = false
                }
                return
            }

            recordingSessionStore.markBackgroundChunkFlushInProgress()

            do {
                try await transcribeBackgroundChunk(chunk, meetingID: meetingID)
                settingsStore.markASRStreamSucceeded()
                if recordingSessionStore.isBackgroundChunkingActive {
                    recordingSessionStore.markBackgroundChunkReadyForMore()
                }
            } catch is CancellationError {
                return
            } catch {
                clearBackgroundShadowBuffer(keepingCapacity: false)
                shouldFlushBackgroundTranscriptTail = false
                recordingSessionStore.markBackgroundChunkFailureNeedsRepair()
                settingsStore.markASRStreamFailed(message: error.localizedDescription)
                return
            }
        }
    }

    private func dequeueBackgroundTranscriptChunk(forceFlushTail: Bool) -> BackgroundTranscriptChunk? {
        guard let startTimeMS = recordingSessionStore.backgroundChunkStartTimeMS else {
            return nil
        }

        let availableByteCount = backgroundTranscriptPCMBuffer.count
        let targetByteCount = backgroundChunkTargetByteCount
        let chunkByteCount: Int

        if availableByteCount >= targetByteCount {
            chunkByteCount = targetByteCount
        } else if forceFlushTail, availableByteCount > 0 {
            chunkByteCount = availableByteCount
            shouldFlushBackgroundTranscriptTail = false
        } else {
            return nil
        }

        let chunkData = Data(backgroundTranscriptPCMBuffer.prefix(chunkByteCount))
        backgroundTranscriptPCMBuffer.removeFirst(chunkByteCount)
        let durationMS = backgroundChunkDurationMS(forPCMByteCount: chunkByteCount)
        backgroundShadowBufferStartTimeMS = startTimeMS + durationMS
        recordingSessionStore.backgroundChunkStartTimeMS = startTimeMS + durationMS
        recordingSessionStore.markBackgroundChunkBufferDuration(
            backgroundChunkDurationMS(forPCMByteCount: backgroundTranscriptPCMBuffer.count)
        )

        return BackgroundTranscriptChunk(
            pcmData: chunkData,
            startTimeMS: startTimeMS,
            durationMS: durationMS
        )
    }

    private func transcribeBackgroundChunk(_ chunk: BackgroundTranscriptChunk, meetingID: String) async throws {
        await checkBackendHealth(force: false)

        guard settingsStore.apiReachable else {
            throw APIClientError.requestFailed(
                settingsStore.blockingMessage(for: .backend) ?? "\(AppEnvironment.cloudName) 暂时不可用。"
            )
        }

        let workspaceID = try await resolveWorkspaceID(for: meetingID)

        for attempt in 1 ... 2 {
            let wavURL = try PCMTemporaryWAVWriter.write(pcmData: chunk.pcmData)
            defer { try? FileManager.default.removeItem(at: wavURL) }

            do {
                var results: [ASRFinalResult] = []
                try await audioFileTranscriptionService.transcribe(
                    fileURL: wavURL,
                    workspaceID: workspaceID,
                    onPhaseChange: { _ in },
                    onPartialText: { _ in },
                    onFinalResult: { result in
                        results.append(result)
                    }
                )

                guard let meeting = meeting(withID: meetingID) else { return }
                try mergeBackgroundTranscriptResults(
                    results,
                    into: meeting,
                    gapStartTimeMS: chunk.startTimeMS,
                    gapEndTimeMS: chunk.startTimeMS + chunk.durationMS,
                    timestampsAreRelativeToGap: true,
                    allowsEmptyResults: true
                )
                return
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                guard attempt == 1 else { throw error }
                try? await Task.sleep(for: Self.backgroundChunkRetryDelay)
            }
        }
    }

    private func resolveWorkspaceID(for meetingID: String) async throws -> String? {
        let existingWorkspaceID = meeting(withID: meetingID)?.hiddenWorkspaceId ?? settingsStore.hiddenWorkspaceID
        let workspaceID: String?
        if let existingWorkspaceID {
            workspaceID = existingWorkspaceID
        } else {
            workspaceID = await bootstrapHiddenWorkspace(force: false, surfaceBlockingError: false)
        }

        if let meeting = meeting(withID: meetingID), meeting.hiddenWorkspaceId != workspaceID {
            meeting.hiddenWorkspaceId = workspaceID
            meeting.markPending()
            try repository.save()
        }

        return workspaceID
    }

    private func mergeBackgroundTranscriptResults(
        _ results: [ASRFinalResult],
        into meeting: Meeting,
        gapStartTimeMS: Double,
        gapEndTimeMS: Double,
        timestampsAreRelativeToGap: Bool,
        allowsEmptyResults: Bool = false
    ) throws {
        let effectiveGapEndTimeMS = min(
            gapEndTimeMS,
            meeting.orderedSegments
                .filter { $0.startTime > gapStartTimeMS }
                .map(\.startTime)
                .min() ?? gapEndTimeMS
        )
        guard effectiveGapEndTimeMS > gapStartTimeMS else {
            return
        }

        let speaker = meeting.recordingMode == .fileMix ? "混合音频" : "麦克风"
        let normalizedResults = results.compactMap { result -> ASRFinalResult? in
            let normalizedText = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalizedText.isEmpty else { return nil }

            let startTime = timestampsAreRelativeToGap ? result.startTime + gapStartTimeMS : result.startTime
            let endTime = timestampsAreRelativeToGap ? result.endTime + gapStartTimeMS : result.endTime
            guard max(endTime, startTime) > gapStartTimeMS, startTime < effectiveGapEndTimeMS else {
                return nil
            }

            return ASRFinalResult(
                text: normalizedText,
                startTime: startTime,
                endTime: max(endTime, startTime)
            )
        }

        guard !normalizedResults.isEmpty else {
            if allowsEmptyResults {
                return
            }
            throw APIClientError.requestFailed("补转写未返回任何结果。")
        }

        let preservedSegments = meeting.orderedSegments.filter {
            $0.endTime <= gapStartTimeMS || $0.startTime >= effectiveGapEndTimeMS
        }
        let insertedSegments = normalizedResults.enumerated().map { index, result in
            makeTranscriptSegment(result, speaker: speaker, orderIndex: index)
        }
        let mergedSegments = (preservedSegments + insertedSegments)
            .sorted {
                if $0.startTime == $1.startTime {
                    return $0.orderIndex < $1.orderIndex
                }
                return $0.startTime < $1.startTime
            }
            .enumerated()
            .map { index, segment -> TranscriptSegment in
                segment.orderIndex = index
                return segment
            }

        repository.replaceSegments(for: meeting, with: mergedSegments)
        meeting.markPending()
        try repository.save()
        loadMeetings()
    }

    private var backgroundChunkBytesPerMillisecond: Double {
        (Double(Int(PCMConverter.targetSampleRate)) * 2) / 1000
    }

    private var backgroundChunkTargetByteCount: Int {
        Int((Self.backgroundChunkTargetDurationMS * backgroundChunkBytesPerMillisecond).rounded())
    }

    private func backgroundPCMByteCount(forDurationMS durationMS: Double) -> Int {
        guard durationMS > 0 else { return 0 }
        return Int((durationMS * backgroundChunkBytesPerMillisecond).rounded())
    }

    private func backgroundChunkDurationMS(forPCMByteCount byteCount: Int) -> Double {
        guard byteCount > 0 else { return 0 }
        return Double(byteCount) / backgroundChunkBytesPerMillisecond
    }

    private func handleRecordingProgress(level: Double, duration: Int) {
        recordingSessionStore.pushAudioLevelSample(level)
        recordingSessionStore.durationSeconds = duration
        if recordingSessionStore.phase == .recording,
           lastPublishedLiveActivityDurationSeconds != duration {
            lastPublishedLiveActivityDurationSeconds = duration
            recordingLiveActivityCoordinator.update(phase: .recording, durationSeconds: duration)
        }

        guard let meeting = currentRecordingMeeting() else { return }
        guard meeting.durationSeconds != duration else { return }

        meeting.durationSeconds = duration
        meeting.audioDuration = duration
        meeting.updatedAt = .now
        try? repository.save()
    }

    private func handlePCMChunk(_ data: Data) {
        guard recordingSessionStore.phase == .recording, !data.isEmpty else { return }

        if recordingSessionStore.isAppInBackground {
            if backgroundShadowBufferStartTimeMS == nil {
                backgroundShadowBufferStartTimeMS = currentRecordingDurationMilliseconds()
            }

            backgroundTranscriptPCMBuffer.append(data)

            if recordingSessionStore.isBackgroundChunkingActive {
                recordingSessionStore.markBackgroundChunkBufferDuration(
                    backgroundChunkDurationMS(forPCMByteCount: backgroundTranscriptPCMBuffer.count)
                )
            }

            trimBackgroundShadowBufferIfNeeded()
            asrService.enqueuePCM(data)

            if recordingSessionStore.isBackgroundChunkingActive,
               let meetingID = recordingSessionStore.meetingID {
                scheduleBackgroundChunkTranscriptionIfNeeded(for: meetingID)
            }
            return
        }

        asrService.enqueuePCM(data)
    }

    private func handleFinalTranscript(_ result: ASRFinalResult) {
        guard let meeting = currentRecordingMeeting() else { return }
        let speaker = meeting.recordingMode == .fileMix ? "混合音频" : "麦克风"
        appendTranscriptSegment(result, to: meeting, speaker: speaker)
        recordingSessionStore.currentPartial = ""
        trimBackgroundShadowBuffer(through: result.endTime)
    }

    private func appendTranscriptSegment(_ result: ASRFinalResult, to meeting: Meeting, speaker: String) {
        let nextIndex = (meeting.orderedSegments.last?.orderIndex ?? -1) + 1
        let segment = makeTranscriptSegment(result, speaker: speaker, orderIndex: nextIndex)
        segment.meeting = meeting

        meeting.segments.append(segment)
        meeting.markPending()

        do {
            try repository.save()
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    private func makeTranscriptSegments(from results: [ASRFinalResult], speaker: String) -> [TranscriptSegment] {
        results.enumerated().map { index, result in
            makeTranscriptSegment(result, speaker: speaker, orderIndex: index)
        }
    }

    private func makeTranscriptSegment(
        _ result: ASRFinalResult,
        speaker: String,
        orderIndex: Int
    ) -> TranscriptSegment {
        TranscriptSegment(
            speaker: speaker,
            text: result.text,
            startTime: result.startTime,
            endTime: max(result.endTime, result.startTime),
            isFinal: true,
            orderIndex: orderIndex
        )
    }

    private func startBackendPreparationIfNeeded() {
        guard !didStartBackendPreparation else { return }
        guard !isUITestRuntime else { return }
        didStartBackendPreparation = true
        scheduleBackendPreparationIfNeeded(retryDelays: [.zero, .seconds(2), .seconds(6)])
    }

    private func scheduleBackendPreparationIfNeeded(retryDelays: [Duration]) {
        guard !isUITestRuntime else { return }
        guard backendPreparationTask == nil else { return }

        backendPreparationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.backendPreparationTask = nil }

            for (index, delay) in retryDelays.enumerated() {
                if delay != .zero {
                    try? await Task.sleep(for: delay)
                }

                guard !Task.isCancelled else { return }

                if await self.prepareBackendForUse(markBackendUnreachableOnFailure: index == retryDelays.count - 1) {
                    return
                }
            }
        }
    }

    private func prepareBackendForUse(markBackendUnreachableOnFailure: Bool) async -> Bool {
        do {
            let health = try await apiClient.fetchBackendWarmup()
            settingsStore.markBackendReachable(
                message: backendStatusMessage(from: health),
                checkedAt: health.checkedAt
            )
        } catch {
            settingsStore.syncStatusMessage = "正在唤醒云端服务…"
            if markBackendUnreachableOnFailure {
                settingsStore.markBackendUnreachable(message: error.localizedDescription)
                settingsStore.syncStatusMessage = "云端暂时不可用，本地功能仍可使用。"
            }
            return false
        }

        guard await bootstrapHiddenWorkspace(force: false, surfaceBlockingError: false) != nil else {
            settingsStore.syncStatusMessage = "云端工作区初始化失败，稍后自动重试。"
            return false
        }

        let batchResult = await meetingSyncService.syncPendingMeetings()
        do {
            let refreshedCount = try await meetingSyncService.refreshRemoteMeetings()
            loadMeetings()
            settingsStore.syncStatusMessage = "启动同步完成：推送 \(batchResult.syncedCount) 条，刷新 \(refreshedCount) 条。"
        } catch {
            recordBackgroundSyncIssue(
                detail: error.localizedDescription,
                summary: "云端稍后刷新，本地内容已可使用。"
            )
        }

        return true
    }

    private func ensureBackendReachable(force: Bool) async -> Bool {
        if !force, settingsStore.apiReachable, !needsFreshHealthCheck(force: false) {
            return true
        }

        do {
            let health = try await apiClient.fetchBackendWarmup()
            settingsStore.markBackendReachable(
                message: backendStatusMessage(from: health),
                checkedAt: health.checkedAt
            )
        } catch {
            settingsStore.markBackendUnreachable(message: error.localizedDescription)
        }

        return settingsStore.apiReachable
    }

    private func enqueueMeetingChatTask(
        for meetingID: String,
        operation: @escaping @MainActor () async -> Bool
    ) async -> Bool {
        guard chatStreamingTasks[meetingID] == nil else { return false }

        let task = Task { @MainActor [weak self] in
            defer {
                self?.chatStreamingTasks.removeValue(forKey: meetingID)
            }
            return await operation()
        }

        chatStreamingTasks[meetingID] = task
        return await task.value
    }

    private func performSendChatMessage(question: String, for meetingID: String) async -> Bool {
        guard let meeting = meeting(withID: meetingID) else { return false }

        prepareChatSessions(for: meetingID)
        guard await ensureBackendReachable(force: false) else {
            lastErrorMessage = "\(AppEnvironment.cloudName) 暂时不可用。"
            return false
        }

        let session = activeChatSession(for: meetingID)
            ?? chatSessionRepository.makeDraftSession(scope: .meeting, meeting: meeting)
        let payload = MeetingPayloadMapper.makeChatPayload(
            from: meeting,
            session: session,
            question: question
        )
        _ = chatSessionRepository.appendUserMessage(question, to: session)
        let assistantMessage = chatSessionRepository.appendAssistantPlaceholder(to: session)
        draftChatMeetingIDs.remove(meetingID)
        activeChatSessionIDs[meetingID] = session.id
        meeting.markPending()

        do {
            try chatSessionRepository.save()
        } catch {
            lastErrorMessage = error.localizedDescription
            return false
        }

        return await streamMeetingChat(
            payload: payload,
            meeting: meeting,
            session: session,
            assistantMessage: assistantMessage,
            meetingID: meetingID
        ) {
            session.messages.removeAll(where: { $0.id == assistantMessage.id })
            repository.delete(assistantMessage)
            try? repository.save()
        }
    }

    private func performRegenerateLastChatResponse(for meetingID: String) async -> Bool {
        guard let meeting = meeting(withID: meetingID) else { return false }

        prepareChatSessions(for: meetingID)
        guard await ensureBackendReachable(force: false) else {
            lastErrorMessage = "\(AppEnvironment.cloudName) 暂时不可用。"
            return false
        }

        guard let session = activeChatSession(for: meetingID) else {
            return false
        }

        let orderedMessages = session.orderedMessages
        guard let lastUserIndex = orderedMessages.lastIndex(where: { $0.role == "user" }) else {
            return false
        }

        let question = orderedMessages[lastUserIndex].content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty else { return false }

        let history = Array(orderedMessages.prefix(lastUserIndex))
        let trailingMessages = Array(orderedMessages.suffix(from: lastUserIndex + 1))
        let reusableAssistant = trailingMessages.last(where: { $0.role == "assistant" })

        for message in trailingMessages where message.id != reusableAssistant?.id {
            session.messages.removeAll(where: { $0.id == message.id })
            repository.delete(message)
        }

        let payload = MeetingPayloadMapper.makeChatPayload(
            from: meeting,
            history: history,
            question: question
        )
        let assistantMessage = reusableAssistant ?? chatSessionRepository.appendAssistantPlaceholder(to: session)
        let previousAssistantContent = assistantMessage.content
        let previousAssistantTimestamp = assistantMessage.timestamp
        assistantMessage.content = ""
        meeting.markPending()

        do {
            try chatSessionRepository.save()
        } catch {
            assistantMessage.content = previousAssistantContent
            assistantMessage.timestamp = previousAssistantTimestamp
            lastErrorMessage = error.localizedDescription
            return false
        }

        return await streamMeetingChat(
            payload: payload,
            meeting: meeting,
            session: session,
            assistantMessage: assistantMessage,
            meetingID: meetingID
        ) {
            assistantMessage.content = previousAssistantContent
            assistantMessage.timestamp = previousAssistantTimestamp
            try? chatSessionRepository.save()
        }
    }

    private func streamMeetingChat(
        payload: ChatRequestPayload,
        meeting: Meeting,
        session: ChatSession,
        assistantMessage: ChatMessage,
        meetingID: String,
        onFailure: @MainActor () -> Void
    ) async -> Bool {
        streamingChatMeetingIDs.insert(meetingID)
        defer {
            streamingChatMeetingIDs.remove(meetingID)
            loadMeetings()
        }

        do {
            let stream = try await apiClient.streamChat(payload)
            for try await partialContent in stream {
                assistantMessage.content = partialContent
            }

            assistantMessage.timestamp = .now
            session.updatedAt = assistantMessage.timestamp
            meeting.markPending()
            try chatSessionRepository.save()
            settingsStore.markLLMRequestSucceeded()
            await syncMeetingIfPossible(meetingID: meetingID)
            return true
        } catch {
            onFailure()
            lastErrorMessage = error.localizedDescription
            settingsStore.markLLMRequestFailed(message: error.localizedDescription)
            return false
        }
    }

    private func scheduleMeetingSync(meetingID: String, delay: Duration) {
        scheduledSyncTasks[meetingID]?.cancel()
        scheduledSyncTasks[meetingID] = Task { @MainActor [weak self] in
            try? await Task.sleep(for: delay)
            guard let self, !Task.isCancelled else { return }
            await syncMeetingIfPossible(meetingID: meetingID)
            scheduledSyncTasks[meetingID] = nil
        }
    }

    private func syncMeetingIfPossible(
        meetingID: String,
        userVisibleFailurePrefix: String? = nil
    ) async {
        await appActivityCoordinator.performExpiringActivity(named: "sync-meeting-\(meetingID)") { [weak self] in
            guard let self else { return }
            guard let meeting = meeting(withID: meetingID) else { return }

            if meeting.syncState == .deleted {
                guard await ensureBackendReachable(force: false) else {
                    recordBackgroundSyncIssue(
                        detail: settingsStore.blockingMessage(for: .backend) ?? "\(AppEnvironment.cloudName) 暂时不可用。",
                        summary: "后台删除同步失败，将稍后自动重试。"
                    )
                    if let userVisibleFailurePrefix {
                        if userVisibleFailurePrefix == AppStrings.current.speakerDiarizationFailed {
                            lastErrorMessage = nil
                        } else {
                            lastErrorMessage = "\(userVisibleFailurePrefix)：云端暂时不可用，将稍后自动重试。"
                        }
                    }
                    return
                }

                do {
                    try await meetingSyncService.syncMeeting(id: meetingID)
                    loadMeetings()
                } catch {
                    recordBackgroundSyncIssue(
                        detail: error.localizedDescription,
                        summary: "后台删除同步失败，将稍后自动重试。"
                    )
                    if let userVisibleFailurePrefix {
                        if userVisibleFailurePrefix == AppStrings.current.speakerDiarizationFailed {
                            lastErrorMessage = nil
                        } else {
                            lastErrorMessage = "\(userVisibleFailurePrefix)：\(error.localizedDescription)"
                        }
                    }
                    loadMeetings()
                }
                return
            }

            guard await ensureBackendReachable(force: false) else {
                let message = "云端暂时不可用，将稍后自动重试。"
                settingsStore.syncStatusMessage = message
                if let userVisibleFailurePrefix {
                    if userVisibleFailurePrefix == AppStrings.current.speakerDiarizationFailed {
                        lastErrorMessage = nil
                    } else {
                        lastErrorMessage = "\(userVisibleFailurePrefix)：\(message)"
                    }
                }
                return
            }
            guard await bootstrapHiddenWorkspace(force: false, surfaceBlockingError: false) != nil else {
                let message = "云端工作区初始化失败，将稍后自动重试。"
                settingsStore.syncStatusMessage = message
                if let userVisibleFailurePrefix {
                    if userVisibleFailurePrefix == AppStrings.current.speakerDiarizationFailed {
                        lastErrorMessage = nil
                    } else {
                        lastErrorMessage = "\(userVisibleFailurePrefix)：\(message)"
                    }
                }
                return
            }

            do {
                try await meetingSyncService.syncMeeting(id: meetingID)
                loadMeetings()
            } catch {
                recordBackgroundSyncIssue(
                    detail: error.localizedDescription,
                    summary: "后台同步失败，将稍后自动重试。"
                )
                if let userVisibleFailurePrefix {
                    if userVisibleFailurePrefix == AppStrings.current.speakerDiarizationFailed {
                        lastErrorMessage = nil
                    } else {
                        lastErrorMessage = "\(userVisibleFailurePrefix)：\(error.localizedDescription)"
                    }
                }
                loadMeetings()
            }
        }
    }

    private func finalizeStoppedMeeting(meetingID: String) async {
        guard let currentMeeting = meeting(withID: meetingID) else { return }

        if currentMeeting.speakerDiarizationState == .processing {
            await syncMeetingIfPossible(
                meetingID: meetingID,
                userVisibleFailurePrefix: AppStrings.current.speakerDiarizationFailed
            )
        }

        guard let meeting = meeting(withID: meetingID) else { return }
        if meeting.transcriptPipelineState == .initializing || meeting.transcriptPipelineState == .failed {
            loadMeetings()
            return
        }

        let transcript = MeetingPayloadMapper.transcriptText(from: meeting)
        let canRunAIFinalization: Bool
        if transcript.isEmpty {
            canRunAIFinalization = false
        } else {
            canRunAIFinalization = await ensureBackendReachable(force: false)
        }

        if meeting.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           canRunAIFinalization {
            do {
                generatingTitleMeetingIDs.insert(meetingID)
                defer { generatingTitleMeetingIDs.remove(meetingID) }
                let titleResponse = try await apiClient.generateMeetingTitle(
                    transcript: transcript,
                    durationSeconds: meeting.durationSeconds,
                    meetingDate: meeting.date
                )
                let generatedTitle = titleResponse.title.trimmingCharacters(in: .whitespacesAndNewlines)
                if !generatedTitle.isEmpty {
                    meeting.title = generatedTitle
                    meeting.markPending()
                    try repository.save()
                    settingsStore.markLLMRequestSucceeded(provider: titleResponse.provider)
                    loadMeetings()
                }
            } catch {
                let message = "标题生成失败：\(error.localizedDescription)"
                lastErrorMessage = message
                settingsStore.syncStatusMessage = message
                settingsStore.markLLMRequestFailed(message: error.localizedDescription)
            }
        }

        if meeting.enhancedNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           canRunAIFinalization {
            do {
                let transcriptFingerprint = meeting.transcriptFingerprint
                enhancingMeetingIDs.insert(meetingID)
                defer { enhancingMeetingIDs.remove(meetingID) }
                let response = try await apiClient.enhanceNotes(MeetingPayloadMapper.makeEnhancePayload(from: meeting))
                let content = normalizeGeneratedNotes(response.content)
                if !content.isEmpty {
                    meeting.enhancedNotes = content
                    meeting.aiNotesFreshnessState = .fresh
                    meeting.lastAINotesTranscriptFingerprint = transcriptFingerprint
                    meeting.markPending()
                    try repository.save()
                    settingsStore.markLLMRequestSucceeded(provider: response.provider)
                    loadMeetings()
                }
            } catch {
                let message = "AI 后处理失败：\(error.localizedDescription)"
                lastErrorMessage = message
                settingsStore.syncStatusMessage = message
                settingsStore.markLLMRequestFailed(message: error.localizedDescription)
            }
        }

        if meeting.syncState != .synced || meeting.lastSyncedAt == nil {
            await syncMeetingIfPossible(meetingID: meetingID, userVisibleFailurePrefix: "会议同步失败")
        }
    }

    private func updateTranscriptNotesFreshnessIfNeeded(for meeting: Meeting) {
        let notes = meeting.enhancedNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !notes.isEmpty else {
            meeting.aiNotesFreshnessState = meeting.aiNotesFreshnessState.settingTranscriptChanges(false)
            return
        }

        guard let lastTranscriptFingerprint = meeting.lastAINotesTranscriptFingerprint else {
            return
        }

        let hasTranscriptChanged = lastTranscriptFingerprint != meeting.transcriptFingerprint
        meeting.aiNotesFreshnessState = meeting.aiNotesFreshnessState.settingTranscriptChanges(hasTranscriptChanged)
    }

    private func needsFreshHealthCheck(force: Bool) -> Bool {
        if force {
            return true
        }

        guard let lastHealthCheckAt = settingsStore.lastHealthCheckAt else {
            return true
        }

        return Date().timeIntervalSince(lastHealthCheckAt) > 60
    }

    private func shouldAutoRefreshEnhancedNotesAfterMeetingTypeChange(for meeting: Meeting) -> Bool {
        !meeting.enhancedNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func migrateLegacyChatSessionsIfNeeded() {
        for meeting in meetings {
            try? chatSessionRepository.migrateLegacyMeetingChatsIfNeeded(for: meeting)
        }
    }

    private func backendStatusMessage(from health: RemoteBackendHealth?) -> String {
        guard let health else {
            return "\(AppEnvironment.cloudName) 在线"
        }

        if health.database == false {
            return "\(AppEnvironment.cloudName) 已响应，数据库异常"
        }

        if health.ok == false {
            return "\(AppEnvironment.cloudName) 已响应"
        }

        return "\(AppEnvironment.cloudName) 在线"
    }

    private func startASRIfPossible(for meetingID: String) async {
        guard recordingSessionStore.meetingID == meetingID,
              recordingSessionStore.phase == .recording else { return }
        cancelASRReconnect()

        let existingWorkspaceID = meeting(withID: meetingID)?.hiddenWorkspaceId ?? settingsStore.hiddenWorkspaceID
        let workspaceID: String?
        if let existingWorkspaceID {
            workspaceID = existingWorkspaceID
        } else {
            workspaceID = await bootstrapHiddenWorkspace(force: false, surfaceBlockingError: false)
        }

        guard recordingSessionStore.meetingID == meetingID,
              recordingSessionStore.phase == .recording else { return }

        do {
            try await asrService.startStreaming(workspaceID: workspaceID)
            asrReconnectAttempt = 0
        } catch {
            guard recordingSessionStore.meetingID == meetingID else { return }
            recordingSessionStore.markTranscriptCoverageGap()
            recordingSessionStore.asrState = .degraded
            recordingSessionStore.infoBanner = nil
            recordingSessionStore.errorBanner = nil
            settingsStore.markASRStreamFailed(message: error.localizedDescription)
            scheduleBackendPreparationIfNeeded(retryDelays: [.zero, .seconds(2)])
            scheduleASRReconnect(for: meetingID)
        }
    }

    private func updateKeepScreenAwake() {
        let shouldKeepScreenAwake: Bool

        switch recordingSessionStore.phase {
        case .starting, .recording:
            shouldKeepScreenAwake = true
        case .idle, .paused, .stopping:
            shouldKeepScreenAwake = false
        }

        appActivityCoordinator.setKeepScreenAwake(shouldKeepScreenAwake)
    }

    private func scheduleASRReconnect(for meetingID: String, delay: Duration? = nil) {
        guard recordingSessionStore.meetingID == meetingID,
              recordingSessionStore.phase == .recording else {
            return
        }

        let resolvedDelay = delay ?? nextASRReconnectDelay()
        asrReconnectTask?.cancel()
        asrReconnectTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: resolvedDelay)
            guard let self, !Task.isCancelled else { return }
            guard self.recordingSessionStore.meetingID == meetingID,
                  self.recordingSessionStore.phase == .recording,
                  self.recordingSessionStore.asrState != .connected else {
                self.asrReconnectTask = nil
                return
            }

            self.asrReconnectTask = nil
            await self.startASRIfPossible(for: meetingID)

            if self.recordingSessionStore.asrState != .connected,
               self.recordingSessionStore.phase == .recording {
                self.scheduleASRReconnect(for: meetingID)
            } else {
                self.asrReconnectTask = nil
            }
        }
    }

    private func nextASRReconnectDelay() -> Duration {
        let index = min(asrReconnectAttempt, Self.asrReconnectDelays.count - 1)
        asrReconnectAttempt += 1
        return Self.asrReconnectDelays[index]
    }

    private func cancelASRReconnect() {
        asrReconnectTask?.cancel()
        asrReconnectTask = nil
        asrReconnectAttempt = 0
    }

    private func recordBackgroundSyncIssue(detail: String, summary: String) {
        settingsStore.syncStatusMessage = summary
        settingsStore.workspaceStatusMessage = detail
    }

    private func cancelAllBackgroundTasks() {
        backendPreparationTask?.cancel()
        backendPreparationTask = nil
        asrReconnectTask?.cancel()
        asrReconnectTask = nil
        backgroundTranscriptBackfillTask?.cancel()
        backgroundTranscriptBackfillTask = nil

        for task in scheduledSyncTasks.values {
            task.cancel()
        }
        scheduledSyncTasks.removeAll()

        for task in fileTranscriptionTasks.values {
            task.cancel()
        }
        fileTranscriptionTasks.removeAll()

        for task in noteAttachmentTextTasks.values {
            task.cancel()
        }
        noteAttachmentTextTasks.removeAll()
        noteAttachmentTaskTokens.removeAll()
        clearBackgroundShadowBuffer(keepingCapacity: false)
        shouldFlushBackgroundTranscriptTail = false

        Task { [weak asrService] in
            await asrService?.stopStreaming()
        }
    }

    private func stopActiveRecordingAndDiscardArtifactIfNeeded() {
        guard recordingSessionStore.phase != .idle else { return }

        if let artifact = try? audioRecorderService.stopRecording(),
           FileManager.default.fileExists(atPath: artifact.fileURL.path) {
            try? FileManager.default.removeItem(at: artifact.fileURL)
        }

        clearBackgroundShadowBuffer(keepingCapacity: false)
        recordingSessionStore.reset()
        updateKeepScreenAwake()
    }

    private func removeLocalAudioIfNeeded(for meeting: Meeting) {
        let fileManager = FileManager.default

        for path in [meeting.audioLocalPath, meeting.sourceAudioLocalPath].compactMap({ $0 }) {
            guard fileManager.fileExists(atPath: path) else {
                continue
            }

            try? fileManager.removeItem(atPath: path)
        }
    }

    private func stageMeetingForDeferredDeletion(_ meeting: Meeting) throws {
        discardLocalMeetingState(for: meeting)
        removeLocalAudioIfNeeded(for: meeting)
        meeting.syncState = .deleted
        meeting.updatedAt = .now
        try repository.save()
        loadMeetings()
    }

    private func deleteMeetingLocally(_ meeting: Meeting) throws {
        discardLocalMeetingState(for: meeting)
        removeLocalAudioIfNeeded(for: meeting)
        try repository.delete(meeting)
        loadMeetings()
    }

    private func discardLocalMeetingState(for meeting: Meeting) {
        scheduledSyncTasks[meeting.id]?.cancel()
        scheduledSyncTasks[meeting.id] = nil
        fileTranscriptionTasks[meeting.id]?.cancel()
        fileTranscriptionTasks[meeting.id] = nil
        cancelNoteAttachmentTextTask(for: meeting.id)
        transcribingMeetingIDs.remove(meeting.id)
        fileTranscriptionStatuses.removeValue(forKey: meeting.id)
        fileTranscriptionPartials.removeValue(forKey: meeting.id)
        enhancingMeetingIDs.remove(meeting.id)
        generatingTitleMeetingIDs.remove(meeting.id)
        streamingChatMeetingIDs.remove(meeting.id)

        // Clean up annotation images on disk (SwiftData cascade handles the model)
        AnnotationImageStorage.deleteAllAnnotations(meetingID: meeting.id)
        MeetingNoteAttachmentStorage.deleteAllAttachments(meetingID: meeting.id)

        if selectedMeetingID == meeting.id {
            selectedMeetingID = nil
        }

        if recordingSessionStore.meetingID == meeting.id {
            cancelASRReconnect()
            recordingSessionStore.reset()
            updateKeepScreenAwake()
        }
    }

    private func normalizeGeneratedNotes(_ content: String) -> String {
        content
            .replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: .newlines)
            .map { rawLine in
                let trimmed = rawLine.trimmingCharacters(in: .whitespaces)

                if let unchecked = trimmed.dropPrefix("□ ") {
                    return "- [ ] \(unchecked)"
                }

                if let checked = trimmed.dropPrefix("☑ ") {
                    return "- [x] \(checked)"
                }

                if let bullet = trimmed.dropPrefix("• ") {
                    return "- \(bullet)"
                }

                return trimmed
            }
            .joined(separator: "\n")
            .replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func scheduleNoteAttachmentTextRefresh(for meeting: Meeting) {
        cancelNoteAttachmentTextTask(for: meeting.id)

        let fileNames = meeting.noteAttachmentFileNames
        guard !fileNames.isEmpty else {
            clearNoteAttachmentText(for: meeting)
            persistChanges()
            return
        }

        meeting.noteAttachmentTextStatus = .pending
        meeting.updatedAt = .now
        persistChanges()

        let meetingID = meeting.id
        let taskToken = UUID()
        let imageURLs = fileNames.map {
            MeetingNoteAttachmentStorage.imageURL(meetingID: meetingID, fileName: $0)
        }
        noteAttachmentTaskTokens[meetingID] = taskToken

        noteAttachmentTextTasks[meetingID] = Task { @MainActor [weak self] in
            guard let self else { return }

            do {
                let extractedText = try await noteAttachmentImageTextExtractor.extractText(from: imageURLs)
                guard !Task.isCancelled else { return }
                guard noteAttachmentTaskTokens[meetingID] == taskToken else { return }
                guard let meeting = self.meeting(withID: meetingID) else { return }
                applyNoteAttachmentText(extractedText, to: meeting)
            } catch {
                guard !Task.isCancelled else { return }
                guard noteAttachmentTaskTokens[meetingID] == taskToken else { return }
                guard let meeting = self.meeting(withID: meetingID) else { return }
                meeting.noteAttachmentTextContext = ""
                meeting.noteAttachmentTextStatus = .failed
                meeting.noteAttachmentTextUpdatedAt = .now
                meeting.updatedAt = .now
                persistChanges()
            }

            noteAttachmentTextTasks[meetingID] = nil
            noteAttachmentTaskTokens[meetingID] = nil
        }
    }

    private func applyNoteAttachmentText(_ extractedText: String, to meeting: Meeting) {
        let normalizedText = extractedText.trimmedForImageText
        let previousText = meeting.noteAttachmentTextContext.trimmedForImageText

        meeting.noteAttachmentTextContext = normalizedText
        meeting.noteAttachmentTextStatus = .ready
        meeting.noteAttachmentTextUpdatedAt = .now
        meeting.updatedAt = .now
        markMeetingPendingImageTextRefreshIfNeeded(
            meeting: meeting,
            previousText: previousText,
            newText: normalizedText
        )
        persistChanges()
    }

    private func clearNoteAttachmentText(for meeting: Meeting) {
        meeting.noteAttachmentTextContext = ""
        meeting.noteAttachmentTextStatus = .idle
        meeting.noteAttachmentTextUpdatedAt = nil
        meeting.updatedAt = .now
    }

    private func markMeetingPendingImageTextRefreshIfNeeded(
        meeting: Meeting,
        previousText: String,
        newText: String
    ) {
        guard previousText != newText,
              !meeting.enhancedNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }

        meeting.aiNotesFreshnessState = meeting.aiNotesFreshnessState.settingAttachmentChanges(true)
        meeting.updatedAt = .now
    }

    private func cancelNoteAttachmentTextTask(for meetingID: String) {
        noteAttachmentTextTasks[meetingID]?.cancel()
        noteAttachmentTextTasks[meetingID] = nil
        noteAttachmentTaskTokens[meetingID] = nil
    }
}

private extension String {
    func dropPrefix(_ prefix: String) -> String? {
        guard hasPrefix(prefix) else { return nil }
        return String(dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var trimmedForImageText: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
