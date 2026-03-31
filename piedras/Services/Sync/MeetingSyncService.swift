import Foundation

struct MeetingSyncBatchResult {
    let syncedCount: Int
    let failedCount: Int
}

@MainActor
protocol MeetingSyncServicing: AnyObject {
    @discardableResult
    func syncPendingMeetings() async -> MeetingSyncBatchResult
    func syncMeeting(id: String) async throws
    func refreshRemoteMeetings() async throws -> Int
}

@MainActor
final class MeetingSyncService: MeetingSyncServicing {
    private let repository: MeetingRepository
    private let settingsStore: SettingsStore
    private let apiClient: APIClient

    init(
        repository: MeetingRepository,
        settingsStore: SettingsStore,
        apiClient: APIClient
    ) {
        self.repository = repository
        self.settingsStore = settingsStore
        self.apiClient = apiClient
    }

    @discardableResult
    func syncPendingMeetings() async -> MeetingSyncBatchResult {
        let candidates = (try? repository.fetchMeetings(includeDeleted: true))?
            .filter {
                ($0.syncState == .pending || $0.syncState == .failed || $0.syncState == .deleted)
                    && $0.transcriptPipelineState != .initializing
                    && $0.transcriptPipelineState != .failed
            } ?? []

        var syncedCount = 0
        var failedCount = 0

        for meeting in candidates.sorted(by: { $0.updatedAt < $1.updatedAt }) {
            do {
                try await syncMeeting(id: meeting.id)
                syncedCount += 1
            } catch {
                failedCount += 1
            }
        }

        return MeetingSyncBatchResult(syncedCount: syncedCount, failedCount: failedCount)
    }

    func syncMeeting(id: String) async throws {
        guard let meeting = try repository.meeting(withID: id) else {
            return
        }

        if meeting.syncState == .deleted {
            try await deleteRemoteMeeting(id: id)
            try repository.delete(meeting)
            return
        }

        guard meeting.transcriptPipelineState != .initializing else {
            return
        }

        let workspaceID = meeting.hiddenWorkspaceId ?? settingsStore.hiddenWorkspaceID
        guard let workspaceID else {
            throw APIClientError.requestFailed("隐藏工作区尚未初始化，暂时无法同步会议。")
        }

        meeting.hiddenWorkspaceId = workspaceID
        meeting.syncState = .syncing
        try repository.save()

        do {
            let remoteMeeting = try await apiClient.upsertMeeting(
                MeetingPayloadMapper.makeMeetingUpsertPayload(from: meeting, workspaceID: workspaceID)
            )
            MeetingPayloadMapper.apply(remote: remoteMeeting, to: meeting, repository: repository, baseURL: apiClient.baseURL)
            reconcileTranscriptState(for: meeting)
            if let finalizedMeeting = try await uploadLocalAudioIfNeeded(for: meeting) {
                MeetingPayloadMapper.apply(
                    remote: finalizedMeeting,
                    to: meeting,
                    repository: repository,
                    baseURL: apiClient.baseURL
                )
                reconcileTranscriptState(for: meeting)
            }

            meeting.syncState = .synced
            meeting.lastSyncedAt = .now
            meeting.updatedAt = .now
            try repository.save()
            try pruneLocalAudioIfNeeded(for: meeting)
        } catch {
            if meeting.speakerDiarizationState == .processing {
                meeting.status = .ended
                meeting.transcriptPipelineState = .refining
                meeting.speakerDiarizationErrorMessage = error.localizedDescription
            }
            meeting.syncState = .failed
            try? repository.save()
            throw error
        }
    }

    private func uploadLocalAudioIfNeeded(for meeting: Meeting) async throws -> RemoteMeetingDetail? {
        guard meeting.status == .ended else {
            return nil
        }

        guard let audioLocalPath = meeting.audioLocalPath, !audioLocalPath.isEmpty else {
            return nil
        }

        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: audioLocalPath) else {
            return nil
        }

        let fallbackDuration = max(meeting.audioDuration, meeting.durationSeconds)

        if meeting.speakerDiarizationState == .processing || meeting.speakerDiarizationState == .failed {
            let uploadResponse = try await apiClient.uploadAudio(
                meetingID: meeting.id,
                fileURL: URL(fileURLWithPath: audioLocalPath),
                duration: max(fallbackDuration, 0),
                mimeType: meeting.audioMimeType ?? "audio/m4a",
                requestTranscriptFinalization: true
            )
            apply(uploadResponse: uploadResponse, to: meeting, fallbackDuration: fallbackDuration)
            try repository.save()
            return try await pollForFinalizedMeetingIfNeeded(meetingID: meeting.id, meeting: meeting)
        }

        let uploadResponse = try await apiClient.uploadAudio(
            meetingID: meeting.id,
            fileURL: URL(fileURLWithPath: audioLocalPath),
            duration: max(fallbackDuration, 0),
            mimeType: meeting.audioMimeType ?? "audio/m4a"
        )

        apply(uploadResponse: uploadResponse, to: meeting, fallbackDuration: fallbackDuration)
        try repository.save()
        return nil
    }

    private func pollForFinalizedMeetingIfNeeded(
        meetingID: String,
        meeting: Meeting
    ) async throws -> RemoteMeetingDetail? {
        for _ in 0 ..< 10 {
            try await Task.sleep(nanoseconds: 2_000_000_000)
            let status = try await apiClient.fetchMeetingProcessingStatus(meetingID: meetingID)
            MeetingPayloadMapper.apply(processingStatus: status, to: meeting)
            try repository.save()

            switch status.audioProcessingState {
            case "completed":
                return try await apiClient.getMeeting(id: meetingID)
            case "failed":
                return nil
            default:
                continue
            }
        }

        return nil
    }

    private func apply(
        uploadResponse: RemoteAudioUploadResponse,
        to meeting: Meeting,
        fallbackDuration: Int
    ) {
        meeting.audioRemotePath = apiClient.resolveAbsoluteURLString(uploadResponse.audioUrl) ?? meeting.audioRemotePath
        meeting.audioMimeType = uploadResponse.audioMimeType ?? meeting.audioMimeType
        meeting.audioDuration = uploadResponse.audioDuration ?? fallbackDuration
        meeting.audioUpdatedAt = uploadResponse.audioUpdatedAt ?? meeting.audioUpdatedAt ?? .now

        if let state = uploadResponse.audioProcessingState {
            let processingStatus = RemoteMeetingProcessingStatus(
                meetingId: meeting.id,
                hasAudio: uploadResponse.hasAudio,
                audioProcessingState: state,
                audioProcessingError: uploadResponse.audioProcessingError,
                audioProcessingAttempts: uploadResponse.audioProcessingAttempts,
                audioProcessingRequestedAt: uploadResponse.audioProcessingRequestedAt,
                audioProcessingStartedAt: uploadResponse.audioProcessingStartedAt,
                audioProcessingCompletedAt: uploadResponse.audioProcessingCompletedAt
            )
            MeetingPayloadMapper.apply(processingStatus: processingStatus, to: meeting)
        }
    }

    func refreshRemoteMeetings() async throws -> Int {
        guard let workspaceID = settingsStore.hiddenWorkspaceID else {
            return 0
        }

        let summaries = try await apiClient.listMeetings(workspaceID: workspaceID)

        for summary in summaries {
            let localMeeting = try repository.meeting(withID: summary.id)
            if let localMeeting,
               localMeeting.syncState == .pending
                || localMeeting.syncState == .syncing
                || localMeeting.syncState == .deleted {
                continue
            }

            let remoteDetail = try await apiClient.getMeeting(id: summary.id)
            if let localMeeting {
                MeetingPayloadMapper.apply(
                    remote: remoteDetail,
                    to: localMeeting,
                    repository: repository,
                    baseURL: apiClient.baseURL
                )
            } else {
                repository.insert(MeetingPayloadMapper.makeMeeting(from: remoteDetail, baseURL: apiClient.baseURL))
            }
        }

        try repository.save()
        return summaries.count
    }

    func deleteRemoteMeeting(id: String) async throws {
        try await apiClient.deleteMeeting(id: id)
    }

    private func pruneLocalAudioIfNeeded(for meeting: Meeting) throws {
        guard meeting.status == .ended else {
            return
        }

        guard let audioLocalPath = meeting.audioLocalPath else {
            return
        }

        // Keep the local recording available for transcript playback after sync.
        guard FileManager.default.fileExists(atPath: audioLocalPath) else {
            meeting.audioLocalPath = nil
            try repository.save()
            return
        }
    }

    private func reconcileTranscriptState(for meeting: Meeting) {
        switch meeting.status {
        case .transcribing:
            meeting.transcriptPipelineState = .initializing
        case .transcriptionFailed:
            meeting.transcriptPipelineState = .failed
        case .ended:
            meeting.transcriptPipelineState = meeting.speakerDiarizationState == .processing ? .refining : .ready
        case .idle, .recording, .paused:
            meeting.transcriptPipelineState = .idle
        }

        updateTranscriptNotesFreshnessIfNeeded(for: meeting)
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
}
