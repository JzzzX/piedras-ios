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
                    && $0.status != .transcribing
                    && $0.status != .transcriptionFailed
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

        guard meeting.status != .transcribing else {
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
            if let finalizedMeeting = try await uploadLocalAudioIfNeeded(for: meeting) {
                MeetingPayloadMapper.apply(
                    remote: finalizedMeeting,
                    to: meeting,
                    repository: repository,
                    baseURL: apiClient.baseURL
                )
            }

            meeting.syncState = .synced
            meeting.lastSyncedAt = .now
            meeting.updatedAt = .now
            try repository.save()
            try pruneLocalAudioIfNeeded(for: meeting)
        } catch {
            if meeting.speakerDiarizationState == .processing {
                meeting.status = .ended
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
            let remoteMeeting = try await apiClient.uploadAudioAndFinalizeTranscript(
                meetingID: meeting.id,
                fileURL: URL(fileURLWithPath: audioLocalPath),
                duration: max(fallbackDuration, 0),
                mimeType: meeting.audioMimeType ?? "audio/m4a"
            )
            meeting.speakerDiarizationState = .ready
            meeting.speakerDiarizationErrorMessage = nil
            try repository.save()
            return remoteMeeting
        }

        let uploadResponse = try await apiClient.uploadAudio(
            meetingID: meeting.id,
            fileURL: URL(fileURLWithPath: audioLocalPath),
            duration: max(fallbackDuration, 0),
            mimeType: meeting.audioMimeType ?? "audio/m4a"
        )

        meeting.audioRemotePath = apiClient.resolveAbsoluteURLString(uploadResponse.audioUrl) ?? meeting.audioRemotePath
        meeting.audioMimeType = uploadResponse.audioMimeType ?? meeting.audioMimeType
        meeting.audioDuration = uploadResponse.audioDuration ?? fallbackDuration
        meeting.audioUpdatedAt = uploadResponse.audioUpdatedAt ?? meeting.audioUpdatedAt ?? .now
        try repository.save()
        return nil
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
}
