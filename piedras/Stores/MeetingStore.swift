import Foundation
import Observation
import SwiftUI

@MainActor
@Observable
final class MeetingStore {
    private let repository: MeetingRepository
    private let settingsStore: SettingsStore
    private let recordingSessionStore: RecordingSessionStore
    private let appActivityCoordinator: AppActivityCoordinator
    private let audioRecorderService: AudioRecorderService
    private let apiClient: APIClient
    private let asrService: ASRService
    private let workspaceBootstrapService: WorkspaceBootstrapService
    private let meetingSyncService: MeetingSyncService

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
    var streamingChatMeetingIDs: Set<String> = []
    private var didLoad = false
    private var didStartBackendPreparation = false
    private var scheduledSyncTasks: [String: Task<Void, Never>] = [:]

    init(
        repository: MeetingRepository,
        settingsStore: SettingsStore,
        recordingSessionStore: RecordingSessionStore,
        appActivityCoordinator: AppActivityCoordinator,
        audioRecorderService: AudioRecorderService,
        apiClient: APIClient,
        asrService: ASRService,
        workspaceBootstrapService: WorkspaceBootstrapService,
        meetingSyncService: MeetingSyncService
    ) {
        self.repository = repository
        self.settingsStore = settingsStore
        self.recordingSessionStore = recordingSessionStore
        self.appActivityCoordinator = appActivityCoordinator
        self.audioRecorderService = audioRecorderService
        self.apiClient = apiClient
        self.asrService = asrService
        self.workspaceBootstrapService = workspaceBootstrapService
        self.meetingSyncService = meetingSyncService

        self.audioRecorderService.onProgress = { [weak self] level, duration in
            self?.handleRecordingProgress(level: level, duration: duration)
        }
        self.audioRecorderService.onPCMData = { [weak self] data in
            self?.handlePCMChunk(data)
        }
        self.asrService.onStateChange = { [weak self] state in
            self?.recordingSessionStore.asrState = state
            if state == .connected {
                self?.recordingSessionStore.infoBanner = nil
                self?.recordingSessionStore.errorBanner = nil
            }
        }
        self.asrService.onPartialText = { [weak self] partial in
            self?.recordingSessionStore.currentPartial = partial
        }
        self.asrService.onFinalResult = { [weak self] result in
            self?.handleFinalTranscript(result)
        }
        self.asrService.onError = { [weak self] message in
            self?.recordingSessionStore.errorBanner = message
        }
    }

    var selectedMeeting: Meeting? {
        guard let selectedMeetingID else { return nil }
        return try? repository.meeting(withID: selectedMeetingID)
    }

    func loadIfNeeded() {
        guard !didLoad else { return }
        didLoad = true
        loadMeetings()
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
    func createMeeting() -> Meeting? {
        do {
            let meeting = try repository.createDraftMeeting(hiddenWorkspaceID: settingsStore.hiddenWorkspaceID)
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

    func persistChanges() {
        do {
            try repository.save()
            loadMeetings()
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func deleteMeeting(id: String) {
        Task { @MainActor [weak self] in
            await self?.deleteMeetingRemotelyIfNeeded(id: id)
        }
    }

    func startRecording(meetingID: String) async {
        if let activeMeetingID = recordingSessionStore.meetingID,
           activeMeetingID != meetingID,
           recordingSessionStore.phase != .idle {
            recordingSessionStore.errorBanner = "请先结束当前录音，再开始新的会议。"
            return
        }

        guard let meeting = meeting(withID: meetingID) else { return }

        do {
            recordingSessionStore.errorBanner = nil
            recordingSessionStore.infoBanner = nil
            recordingSessionStore.currentPartial = ""
            recordingSessionStore.asrState = .connecting
            recordingSessionStore.meetingID = meetingID
            recordingSessionStore.phase = .starting
            updateKeepScreenAwake()
            let fileURL = try await audioRecorderService.startRecording(meetingID: meetingID)
            recordingSessionStore.phase = .recording
            updateKeepScreenAwake()
            meeting.date = .now
            meeting.audioLocalPath = fileURL.path
            meeting.audioMimeType = "audio/m4a"
            meeting.audioUpdatedAt = .now
            meeting.status = .recording
            meeting.markPending()
            try repository.save()
            selectedMeetingID = meetingID
            loadMeetings()
            Task { @MainActor [weak self] in
                await self?.startASRIfPossible(for: meetingID)
            }
        } catch {
            recordingSessionStore.errorBanner = error.localizedDescription
            recordingSessionStore.phase = .idle
            recordingSessionStore.meetingID = nil
            recordingSessionStore.asrState = .idle
            updateKeepScreenAwake()
            lastErrorMessage = error.localizedDescription
        }
    }

    func pauseRecording() async {
        guard let meeting = currentRecordingMeeting() else { return }

        do {
            try audioRecorderService.pauseRecording()
            await asrService.stopStreaming()
            recordingSessionStore.phase = .paused
            recordingSessionStore.currentPartial = ""
            recordingSessionStore.infoBanner = nil
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
        guard let meeting = currentRecordingMeeting() else { return }

        do {
            try audioRecorderService.resumeRecording()
            recordingSessionStore.phase = .recording
            recordingSessionStore.asrState = .connecting
            recordingSessionStore.infoBanner = nil
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
        guard let meeting = currentRecordingMeeting() else { return }

        do {
            recordingSessionStore.phase = .stopping
            recordingSessionStore.infoBanner = nil
            updateKeepScreenAwake()
            await asrService.stopStreaming()
            let artifact = try audioRecorderService.stopRecording()
            meeting.status = .ended
            meeting.audioLocalPath = artifact.fileURL.path
            meeting.audioMimeType = artifact.mimeType
            meeting.audioDuration = artifact.durationSeconds
            meeting.audioUpdatedAt = .now
            meeting.durationSeconds = max(meeting.durationSeconds, artifact.durationSeconds)
            meeting.markPending()
            try repository.save()
            recordingSessionStore.reset()
            updateKeepScreenAwake()
            loadMeetings()
            await appActivityCoordinator.performExpiringActivity(named: "finish-meeting-\(meeting.id)") { [weak self] in
                await self?.finalizeStoppedMeeting(meetingID: meeting.id)
            }
        } catch {
            recordingSessionStore.errorBanner = error.localizedDescription
        }
    }

    func handleScenePhaseChange(_ phase: ScenePhase) {
        let isBackground = phase == .background
        recordingSessionStore.isAppInBackground = isBackground

        guard let meetingID = recordingSessionStore.meetingID else {
            recordingSessionStore.infoBanner = nil
            return
        }

        switch phase {
        case .background:
            if recordingSessionStore.phase == .recording {
                recordingSessionStore.currentPartial = ""
                recordingSessionStore.infoBanner = "应用已切到后台，录音会继续；实时转写会在回到前台后自动恢复。"
            }
        case .active:
            if recordingSessionStore.phase == .recording,
               [.idle, .degraded, .disconnected].contains(recordingSessionStore.asrState) {
                recordingSessionStore.infoBanner = "已回到前台，正在恢复实时转写连接。"
                Task { @MainActor [weak self] in
                    await self?.startASRIfPossible(for: meetingID)
                }
            } else if recordingSessionStore.phase != .recording {
                recordingSessionStore.infoBanner = nil
            }
        case .inactive:
            break
        @unknown default:
            break
        }
    }

    func checkBackendHealth(force: Bool = true) async {
        if !force,
           let lastHealthCheckAt = settingsStore.lastHealthCheckAt,
           Date().timeIntervalSince(lastHealthCheckAt) < 60 {
            return
        }

        if settingsStore.isCheckingHealth {
            return
        }

        settingsStore.isCheckingHealth = true
        defer { settingsStore.isCheckingHealth = false }

        do {
            let status = try await apiClient.fetchASRStatus()
            settingsStore.apiReachable = true
            settingsStore.asrReady = status.ready
            settingsStore.backendStatusMessage = "后端在线"
            settingsStore.asrStatusMessage = status.message
            settingsStore.lastHealthCheckAt = .now
        } catch {
            settingsStore.apiReachable = false
            settingsStore.asrReady = false
            settingsStore.backendStatusMessage = error.localizedDescription
            settingsStore.asrStatusMessage = "检查失败"
            settingsStore.lastHealthCheckAt = .now
            lastErrorMessage = error.localizedDescription
        }
    }

    @discardableResult
    func bootstrapHiddenWorkspace(force: Bool = false) async -> String? {
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
            lastErrorMessage = error.localizedDescription
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
                settingsStore.syncStatusMessage = "后端不可达，未执行同步。"
                return
            }

            guard await bootstrapHiddenWorkspace(force: false) != nil else {
                settingsStore.syncStatusMessage = "隐藏工作区初始化失败。"
                return
            }

            let batchResult = await meetingSyncService.syncPendingMeetings()

            do {
                let refreshedCount = try await meetingSyncService.refreshRemoteMeetings()
                loadMeetings()
                settingsStore.syncStatusMessage = "已推送 \(batchResult.syncedCount) 条，失败 \(batchResult.failedCount) 条，刷新 \(refreshedCount) 条。"
            } catch {
                lastErrorMessage = error.localizedDescription
                settingsStore.syncStatusMessage = "推送完成，但刷新远端失败。"
            }
        }
    }

    func generateEnhancedNotes(for meetingID: String) async {
        guard let meeting = meeting(withID: meetingID) else { return }
        guard !enhancingMeetingIDs.contains(meetingID) else { return }
        guard await ensureBackendReachable(force: false) else { return }

        enhancingMeetingIDs.insert(meetingID)
        defer { enhancingMeetingIDs.remove(meetingID) }

        do {
            let response = try await apiClient.enhanceNotes(MeetingPayloadMapper.makeEnhancePayload(from: meeting))
            meeting.enhancedNotes = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
            meeting.markPending()
            try repository.save()
            loadMeetings()
            await syncMeetingIfPossible(meetingID: meetingID)
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func sendChatMessage(question: String, for meetingID: String) async -> Bool {
        let trimmedQuestion = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuestion.isEmpty else { return false }
        guard let meeting = meeting(withID: meetingID) else { return false }
        guard !streamingChatMeetingIDs.contains(meetingID) else { return false }
        guard await ensureBackendReachable(force: false) else { return false }

        let payload = MeetingPayloadMapper.makeChatPayload(from: meeting, question: trimmedQuestion)
        let userOrder = meeting.orderedChatMessages.count
        let userMessage = ChatMessage(role: "user", content: trimmedQuestion, orderIndex: userOrder)
        let assistantMessage = ChatMessage(role: "assistant", content: "", orderIndex: userOrder + 1)

        meeting.chatMessages.append(userMessage)
        meeting.chatMessages.append(assistantMessage)
        meeting.markPending()

        do {
            try repository.save()
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
            meeting.markPending()
            try repository.save()
            await syncMeetingIfPossible(meetingID: meetingID)
            return true
        } catch {
            meeting.chatMessages.removeAll(where: { $0.id == assistantMessage.id })
            repository.delete(assistantMessage)
            try? repository.save()
            lastErrorMessage = error.localizedDescription
            return false
        }
    }

    func isEnhancing(meetingID: String) -> Bool {
        enhancingMeetingIDs.contains(meetingID)
    }

    func isStreamingChat(meetingID: String) -> Bool {
        streamingChatMeetingIDs.contains(meetingID)
    }

    private func currentRecordingMeeting() -> Meeting? {
        guard let meetingID = recordingSessionStore.meetingID else { return nil }
        return meeting(withID: meetingID)
    }

    private func handleRecordingProgress(level: Double, duration: Int) {
        recordingSessionStore.pushAudioLevelSample(level)
        recordingSessionStore.durationSeconds = duration

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

        let nextIndex = (meeting.orderedSegments.last?.orderIndex ?? -1) + 1
        let segment = TranscriptSegment(
            speaker: "麦克风",
            text: result.text,
            startTime: result.startTime,
            endTime: max(result.endTime, result.startTime),
            isFinal: true,
            orderIndex: nextIndex
        )
        segment.meeting = meeting

        meeting.segments.append(segment)
        meeting.markPending()
        recordingSessionStore.currentPartial = ""

        do {
            try repository.save()
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    private func startBackendPreparationIfNeeded() {
        guard !didStartBackendPreparation else { return }
        didStartBackendPreparation = true

        Task { @MainActor [weak self] in
            guard let self else { return }
            await checkBackendHealth(force: true)
            guard settingsStore.apiReachable else { return }
            guard await bootstrapHiddenWorkspace(force: false) != nil else { return }

            let batchResult = await meetingSyncService.syncPendingMeetings()
            do {
                let refreshedCount = try await meetingSyncService.refreshRemoteMeetings()
                loadMeetings()
                settingsStore.syncStatusMessage = "启动同步完成：推送 \(batchResult.syncedCount) 条，刷新 \(refreshedCount) 条。"
            } catch {
                lastErrorMessage = error.localizedDescription
            }
        }
    }

    private func ensureBackendReachable(force: Bool) async -> Bool {
        let shouldCheck = force || settingsStore.lastHealthCheckAt == nil || Date().timeIntervalSince(settingsStore.lastHealthCheckAt ?? .distantPast) > 60
        if shouldCheck {
            await checkBackendHealth(force: true)
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

    private func syncMeetingIfPossible(meetingID: String) async {
        await appActivityCoordinator.performExpiringActivity(named: "sync-meeting-\(meetingID)") { [weak self] in
            guard let self else { return }
            guard await ensureBackendReachable(force: false) else { return }
            guard await bootstrapHiddenWorkspace(force: false) != nil else { return }

            do {
                try await meetingSyncService.syncMeeting(id: meetingID)
                loadMeetings()
            } catch {
                lastErrorMessage = error.localizedDescription
                loadMeetings()
            }
        }
    }

    private func finalizeStoppedMeeting(meetingID: String) async {
        guard let meeting = meeting(withID: meetingID) else { return }

        if meeting.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           !MeetingPayloadMapper.transcriptText(from: meeting).isEmpty,
           await ensureBackendReachable(force: false) {
            do {
                let titleResponse = try await apiClient.generateMeetingTitle(
                    transcript: MeetingPayloadMapper.transcriptText(from: meeting)
                )
                let generatedTitle = titleResponse.title.trimmingCharacters(in: .whitespacesAndNewlines)
                if !generatedTitle.isEmpty {
                    meeting.title = generatedTitle
                    meeting.markPending()
                    try repository.save()
                }
            } catch {
                lastErrorMessage = error.localizedDescription
            }
        }

        await syncMeetingIfPossible(meetingID: meetingID)
    }

    private func startASRIfPossible(for meetingID: String) async {
        guard recordingSessionStore.meetingID == meetingID,
              recordingSessionStore.phase == .recording else { return }

        let existingWorkspaceID = meeting(withID: meetingID)?.hiddenWorkspaceId ?? settingsStore.hiddenWorkspaceID
        let workspaceID: String?
        if let existingWorkspaceID {
            workspaceID = existingWorkspaceID
        } else {
            workspaceID = await bootstrapHiddenWorkspace(force: false)
        }

        guard recordingSessionStore.meetingID == meetingID,
              recordingSessionStore.phase == .recording else { return }

        do {
            try await asrService.startStreaming(workspaceID: workspaceID)
        } catch {
            guard recordingSessionStore.meetingID == meetingID else { return }
            recordingSessionStore.asrState = .degraded
            recordingSessionStore.errorBanner = "实时转写未启动：\(error.localizedDescription)"
        }
    }

    private func deleteMeetingRemotelyIfNeeded(id: String) async {
        await appActivityCoordinator.performExpiringActivity(named: "delete-meeting-\(id)") { [weak self] in
            guard let self, let meeting = meeting(withID: id) else { return }

            if meeting.lastSyncedAt != nil || meeting.syncState == .synced || meeting.audioRemotePath != nil {
                guard await ensureBackendReachable(force: true) else {
                    lastErrorMessage = "后端不可达，已同步会议暂未删除。"
                    return
                }

                do {
                    try await meetingSyncService.deleteRemoteMeeting(id: id)
                } catch {
                    lastErrorMessage = error.localizedDescription
                    return
                }
            }

            do {
                try repository.delete(meeting)
                if selectedMeetingID == id {
                    selectedMeetingID = nil
                }
                if recordingSessionStore.meetingID == id {
                    recordingSessionStore.reset()
                    updateKeepScreenAwake()
                }
                loadMeetings()
            } catch {
                lastErrorMessage = error.localizedDescription
            }
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
}
