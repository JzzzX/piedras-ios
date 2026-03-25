import Foundation
import Observation
import SwiftUI

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

private struct BackgroundTranscriptBackfillSource {
    let fileURL: URL
    let mimeType: String
    let durationSeconds: Int
    let timestampsAreRelativeToGap: Bool
}

@MainActor
@Observable
final class MeetingStore {
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
    private var scheduledSyncTasks: [String: Task<Void, Never>] = [:]
    private var fileTranscriptionTasks: [String: Task<Void, Never>] = [:]
    private var backgroundTranscriptBackfillTask: Task<Void, Never>?
    private var backgroundTranscriptPCMBuffer = Data()
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
        meetingSyncService: any MeetingSyncServicing
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
            self?.bufferBackgroundTranscriptPCMIfNeeded(data)
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
                if self.recordingSessionStore.isAppInBackground,
                   self.recordingSessionStore.isCapturingBackgroundTranscriptGapAudio {
                    self.endBackgroundTranscriptGapIfNeeded()
                }
                if self.recordingSessionStore.pauseReason != .systemInterruption {
                    self.recordingSessionStore.infoBanner = nil
                }
                self.recordingSessionStore.errorBanner = nil
                self.settingsStore.markASRStreamSucceeded()
            } else if self.recordingSessionStore.phase == .recording,
                      self.recordingSessionStore.isAppInBackground,
                      [.idle, .degraded, .disconnected].contains(state) {
                self.beginBackgroundTranscriptGapIfNeeded()
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
                    self.beginBackgroundTranscriptGapIfNeeded()
                } else {
                    self.recordingSessionStore.markTranscriptCoverageGap()
                }
                if let recordingMeetingID {
                    self.scheduleASRReconnect(for: recordingMeetingID, delay: .seconds(2))
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
        backgroundTranscriptPCMBuffer.removeAll(keepingCapacity: false)
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
            try audioRecorderService.pauseRecording()
            await asrService.stopStreaming()
            recordingSessionStore.phase = .paused
            recordingSessionStore.pauseReason = .user
            recordingSessionStore.currentPartial = ""
            recordingSessionStore.infoBanner = nil
            recordingSessionStore.clearBackgroundTranscriptGap()
            backgroundTranscriptPCMBuffer.removeAll(keepingCapacity: false)
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
            backgroundTranscriptBackfillTask?.cancel()
            backgroundTranscriptBackfillTask = nil
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
            }
        case .active:
            if recordingSessionStore.phase == .recording {
                switch audioRecorderService.reconcileForegroundRecording() {
                case .healthy, .recovered:
                    endBackgroundTranscriptGapIfNeeded()
                    scheduleBackgroundTranscriptBackfillIfNeeded(for: meetingID)
                    if [.idle, .degraded, .disconnected].contains(recordingSessionStore.asrState) {
                        Task { @MainActor [weak self] in
                            await self?.startASRIfPossible(for: meetingID)
                        }
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

        enhancingMeetingIDs.insert(meetingID)
        defer { enhancingMeetingIDs.remove(meetingID) }

        do {
            let response = try await apiClient.enhanceNotes(MeetingPayloadMapper.makeEnhancePayload(from: meeting))
            meeting.enhancedNotes = normalizeGeneratedNotes(response.content)
            meeting.hasPendingImageTextRefresh = false
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
        guard let meeting = meeting(withID: meetingID) else { return false }
        guard !streamingChatMeetingIDs.contains(meetingID) else { return false }
        prepareChatSessions(for: meetingID)
        guard await ensureBackendReachable(force: false) else {
            lastErrorMessage = "\(AppEnvironment.cloudName) 暂时不可用。"
            return false
        }

        let session = activeChatSession(for: meetingID) ?? chatSessionRepository.makeDraftSession(scope: .meeting, meeting: meeting)
        let payload = MeetingPayloadMapper.makeChatPayload(from: meeting, session: session, question: trimmedQuestion)
        _ = chatSessionRepository.appendUserMessage(trimmedQuestion, to: session)
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
            session.messages.removeAll(where: { $0.id == assistantMessage.id })
            repository.delete(assistantMessage)
            try? repository.save()
            lastErrorMessage = error.localizedDescription
            settingsStore.markLLMRequestFailed(message: error.localizedDescription)
            return false
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
        transcribingMeetingIDs.contains(meetingID)
            || meeting(withID: meetingID)?.status == .transcribing
    }

    func fileTranscriptionStatus(meetingID: String) -> FileTranscriptionStatusSnapshot? {
        if let status = fileTranscriptionStatuses[meetingID] {
            return status
        }

        guard let meeting = meeting(withID: meetingID) else {
            return nil
        }

        switch meeting.speakerDiarizationState {
        case .idle, .ready:
            return nil
        case .processing:
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
        backgroundTranscriptBackfillTask?.cancel()
        backgroundTranscriptBackfillTask = nil
        let needsTranscriptRepair = recordingSessionStore.needsTranscriptRepairAfterStop
            || recordingSessionStore.hasBackgroundTranscriptGap
            || recordingSessionStore.isBackfillingBackgroundTranscript
        fileTranscriptionTasks[meetingID]?.cancel()
        fileTranscriptionTasks[meetingID] = nil
        transcribingMeetingIDs.remove(meetingID)
        fileTranscriptionStatuses.removeValue(forKey: meetingID)
        fileTranscriptionPartials.removeValue(forKey: meetingID)
        backgroundTranscriptPCMBuffer.removeAll(keepingCapacity: false)

        meeting.status = needsTranscriptRepair ? .transcribing : .ended
        meeting.audioLocalPath = artifact.fileURL.path
        meeting.audioMimeType = artifact.mimeType
        meeting.audioDuration = artifact.durationSeconds
        meeting.audioUpdatedAt = .now
        meeting.durationSeconds = max(meeting.durationSeconds, artifact.durationSeconds)
        meeting.speakerDiarizationState = .processing
        meeting.speakerDiarizationErrorMessage = nil
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

            self.primeEnhancingStateIfNeeded(meetingID: meetingID)
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
            meeting.audioDuration = importedAudio.durationSeconds
            meeting.durationSeconds = importedAudio.durationSeconds
            meeting.audioUpdatedAt = .now
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
            primeEnhancingStateIfNeeded(meetingID: meetingID)
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

    private func appendImportedAudioTranscript(_ result: ASRFinalResult, meetingID: String) {
        guard let meeting = meeting(withID: meetingID) else { return }
        fileTranscriptionPartials[meetingID] = ""
        appendTranscriptSegment(result, to: meeting, speaker: "音频文件")
    }

    private func primeEnhancingStateIfNeeded(meetingID: String) {
        guard let meeting = meeting(withID: meetingID) else { return }
        if !meeting.transcriptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            enhancingMeetingIDs.insert(meetingID)
        }
    }

    private func markFileTranscriptionFailed(meetingID: String, message: String) {
        if let meeting = meeting(withID: meetingID) {
            meeting.status = .transcriptionFailed
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
        lastErrorMessage = nil
        loadMeetings()
    }

    private func recoverInterruptedFileTranscriptionsIfNeeded() {
        let interruptedMeetings = (try? repository.fetchMeetings())?.filter { $0.status == .transcribing } ?? []
        guard !interruptedMeetings.isEmpty else { return }

        for meeting in interruptedMeetings {
            meeting.status = .transcriptionFailed
            meeting.markPending()
            fileTranscriptionStatuses[meeting.id] = FileTranscriptionStatusSnapshot(
                phase: nil,
                errorMessage: AppStrings.current.fileTranscriptionInterrupted,
                showsFailure: true
            )
            fileTranscriptionPartials[meeting.id] = ""
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
            if recordingSessionStore.isAppInBackground {
                beginBackgroundTranscriptGapIfNeeded()
            } else {
                recordingSessionStore.markTranscriptCoverageGap()
            }
        case let .interruptionEnded(shouldResume, _):
            if !shouldResume, recordingSessionStore.isAppInBackground {
                beginBackgroundTranscriptGapIfNeeded()
            }
        case .routeChanged, .mediaServicesWereReset:
            if recordingSessionStore.isAppInBackground {
                beginBackgroundTranscriptGapIfNeeded()
            }
        }
    }

    private func pauseRecordingAfterForegroundInterruption(message: String) async {
        cancelASRReconnect()
        backgroundTranscriptBackfillTask?.cancel()
        backgroundTranscriptBackfillTask = nil
        await asrService.stopStreaming()
        recordingSessionStore.currentPartial = ""
        recordingSessionStore.asrState = .idle
        recordingSessionStore.errorBanner = nil
        recordingSessionStore.infoBanner = message
        recordingSessionStore.phase = .paused
        recordingSessionStore.pauseReason = .systemInterruption
        recordingSessionStore.clearBackgroundTranscriptGap()
        backgroundTranscriptPCMBuffer.removeAll(keepingCapacity: false)
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

    private func beginBackgroundTranscriptGapIfNeeded() {
        guard recordingSessionStore.phase == .recording,
              recordingSessionStore.isAppInBackground else {
            return
        }

        if !recordingSessionStore.hasBackgroundTranscriptGap {
            recordingSessionStore.beginBackgroundTranscriptGap(at: currentRecordingDurationMilliseconds())
            backgroundTranscriptPCMBuffer.removeAll(keepingCapacity: true)
        }

        recordingSessionStore.currentPartial = ""
        recordingSessionStore.infoBanner = nil
    }

    private func endBackgroundTranscriptGapIfNeeded() {
        guard recordingSessionStore.hasBackgroundTranscriptGap,
              recordingSessionStore.backgroundTranscriptGapEndTimeMS == nil else {
            return
        }

        recordingSessionStore.endBackgroundTranscriptGap(at: currentRecordingDurationMilliseconds())
    }

    private func bufferBackgroundTranscriptPCMIfNeeded(_ data: Data) {
        guard recordingSessionStore.isCapturingBackgroundTranscriptGapAudio,
              !data.isEmpty else {
            return
        }

        backgroundTranscriptPCMBuffer.append(data)
    }

    private func scheduleBackgroundTranscriptBackfillIfNeeded(for meetingID: String) {
        guard recordingSessionStore.hasBackgroundTranscriptGap else { return }
        guard backgroundTranscriptBackfillTask == nil else { return }

        backgroundTranscriptBackfillTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.backgroundTranscriptBackfillTask = nil }
            await self.performBackgroundTranscriptBackfill(meetingID: meetingID)
        }
    }

    private func performBackgroundTranscriptBackfill(meetingID: String) async {
        guard let meeting = meeting(withID: meetingID),
              let gapStartTimeMS = recordingSessionStore.backgroundTranscriptGapStartTimeMS else {
            return
        }

        let gapEndTimeMS = max(
            recordingSessionStore.backgroundTranscriptGapEndTimeMS ?? currentRecordingDurationMilliseconds(),
            gapStartTimeMS
        )

        guard gapEndTimeMS > gapStartTimeMS else {
            recordingSessionStore.clearBackgroundTranscriptGap()
            backgroundTranscriptPCMBuffer.removeAll(keepingCapacity: false)
            return
        }

        recordingSessionStore.isBackfillingBackgroundTranscript = true

        let workspaceID: String?

        do {
            await checkBackendHealth(force: false)

            guard settingsStore.apiReachable else {
                throw APIClientError.requestFailed(
                    settingsStore.blockingMessage(for: .backend) ?? "\(AppEnvironment.cloudName) 暂时不可用。"
                )
            }

            workspaceID = try await resolveWorkspaceID(for: meetingID)
            let source = try makeBackgroundTranscriptBackfillSource(
                meetingID: meetingID,
                gapStartTimeMS: gapStartTimeMS,
                gapEndTimeMS: gapEndTimeMS
            )
            defer { try? FileManager.default.removeItem(at: source.fileURL) }

            var results: [ASRFinalResult] = []
            try await audioFileTranscriptionService.transcribe(
                fileURL: source.fileURL,
                workspaceID: workspaceID,
                onPhaseChange: { _ in },
                onPartialText: { _ in },
                onFinalResult: { result in
                    results.append(result)
                }
            )

            try mergeBackgroundTranscriptResults(
                results,
                into: meeting,
                gapStartTimeMS: gapStartTimeMS,
                gapEndTimeMS: gapEndTimeMS,
                timestampsAreRelativeToGap: source.timestampsAreRelativeToGap
            )

            settingsStore.markASRStreamSucceeded()
            recordingSessionStore.clearBackgroundTranscriptGap()
            backgroundTranscriptPCMBuffer.removeAll(keepingCapacity: false)
            if recordingSessionStore.asrState == .connected {
                recordingSessionStore.infoBanner = nil
            }
        } catch is CancellationError {
            return
        } catch {
            recordingSessionStore.markTranscriptCoverageGap()
            recordingSessionStore.isBackfillingBackgroundTranscript = false
            settingsStore.markASRStreamFailed(message: error.localizedDescription)
            lastErrorMessage = error.localizedDescription
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

    private func makeBackgroundTranscriptBackfillSource(
        meetingID: String,
        gapStartTimeMS: Double,
        gapEndTimeMS: Double
    ) throws -> BackgroundTranscriptBackfillSource {
        if !backgroundTranscriptPCMBuffer.isEmpty {
            let wavURL = try PCMTemporaryWAVWriter.write(pcmData: backgroundTranscriptPCMBuffer)
            let durationSeconds = max(1, Int(ceil((gapEndTimeMS - gapStartTimeMS) / 1_000)))
            return BackgroundTranscriptBackfillSource(
                fileURL: wavURL,
                mimeType: "audio/wav",
                durationSeconds: durationSeconds,
                timestampsAreRelativeToGap: true
            )
        }

        if let snapshot = try audioRecorderService.makeRecordingSnapshot() {
            return BackgroundTranscriptBackfillSource(
                fileURL: snapshot.fileURL,
                mimeType: snapshot.mimeType,
                durationSeconds: snapshot.durationSeconds,
                timestampsAreRelativeToGap: false
            )
        }

        throw APIClientError.requestFailed("后台片段暂时无法补齐。")
    }

    private func mergeBackgroundTranscriptResults(
        _ results: [ASRFinalResult],
        into meeting: Meeting,
        gapStartTimeMS: Double,
        gapEndTimeMS: Double,
        timestampsAreRelativeToGap: Bool
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
        guard recordingSessionStore.phase == .recording else { return }
        asrService.enqueuePCM(data)
    }

    private func handleFinalTranscript(_ result: ASRFinalResult) {
        guard let meeting = currentRecordingMeeting() else { return }
        let speaker = meeting.recordingMode == .fileMix ? "混合音频" : "麦克风"
        appendTranscriptSegment(result, to: meeting, speaker: speaker)
        recordingSessionStore.currentPartial = ""
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
        if meeting.speakerDiarizationState == .processing || meeting.speakerDiarizationState == .failed {
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
                enhancingMeetingIDs.insert(meetingID)
                defer { enhancingMeetingIDs.remove(meetingID) }
                let response = try await apiClient.enhanceNotes(MeetingPayloadMapper.makeEnhancePayload(from: meeting))
                let content = normalizeGeneratedNotes(response.content)
                if !content.isEmpty {
                    meeting.enhancedNotes = content
                    meeting.hasPendingImageTextRefresh = false
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

    private func needsFreshHealthCheck(force: Bool) -> Bool {
        if force {
            return true
        }

        guard let lastHealthCheckAt = settingsStore.lastHealthCheckAt else {
            return true
        }

        return Date().timeIntervalSince(lastHealthCheckAt) > 60
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
        } catch {
            guard recordingSessionStore.meetingID == meetingID else { return }
            recordingSessionStore.markTranscriptCoverageGap()
            recordingSessionStore.asrState = .degraded
            recordingSessionStore.infoBanner = nil
            recordingSessionStore.errorBanner = nil
            settingsStore.markASRStreamFailed(message: error.localizedDescription)
            scheduleBackendPreparationIfNeeded(retryDelays: [.zero, .seconds(2)])
            scheduleASRReconnect(for: meetingID, delay: .seconds(2))
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

    private func scheduleASRReconnect(for meetingID: String, delay: Duration) {
        guard recordingSessionStore.meetingID == meetingID,
              recordingSessionStore.phase == .recording else {
            return
        }

        asrReconnectTask?.cancel()
        asrReconnectTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: delay)
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
                self.scheduleASRReconnect(for: meetingID, delay: .seconds(4))
            } else {
                self.asrReconnectTask = nil
            }
        }
    }

    private func cancelASRReconnect() {
        asrReconnectTask?.cancel()
        asrReconnectTask = nil
    }

    private func recordBackgroundSyncIssue(detail: String, summary: String) {
        settingsStore.syncStatusMessage = summary
        settingsStore.workspaceStatusMessage = detail
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
        transcribingMeetingIDs.remove(meeting.id)
        fileTranscriptionStatuses.removeValue(forKey: meeting.id)
        fileTranscriptionPartials.removeValue(forKey: meeting.id)
        enhancingMeetingIDs.remove(meeting.id)
        generatingTitleMeetingIDs.remove(meeting.id)
        streamingChatMeetingIDs.remove(meeting.id)

        // Clean up annotation images on disk (SwiftData cascade handles the model)
        AnnotationImageStorage.deleteAllAnnotations(meetingID: meeting.id)

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
}

private extension String {
    func dropPrefix(_ prefix: String) -> String? {
        guard hasPrefix(prefix) else { return nil }
        return String(dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
