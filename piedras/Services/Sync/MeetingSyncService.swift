import Foundation

struct MeetingSyncBatchResult {
    let syncedCount: Int
    let failedCount: Int
}

@MainActor
final class MeetingSyncService {
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
        let candidates = (try? repository.fetchMeetings())?
            .filter { $0.syncState == .pending || $0.syncState == .failed } ?? []

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

            if shouldUploadAudio(for: meeting) {
                try await uploadAudio(for: meeting)
            }

            meeting.syncState = .synced
            meeting.lastSyncedAt = .now
            meeting.updatedAt = .now
            try repository.save()
        } catch {
            meeting.syncState = .failed
            try? repository.save()
            throw error
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
               localMeeting.syncState == .pending || localMeeting.syncState == .syncing {
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

    private func shouldUploadAudio(for meeting: Meeting) -> Bool {
        guard let audioLocalPath = meeting.audioLocalPath else {
            return false
        }

        guard FileManager.default.fileExists(atPath: audioLocalPath) else {
            return false
        }

        guard let audioUpdatedAt = meeting.audioUpdatedAt else {
            return meeting.audioRemotePath == nil
        }

        return meeting.audioRemotePath == nil || audioUpdatedAt > (meeting.lastSyncedAt ?? .distantPast)
    }

    private func uploadAudio(for meeting: Meeting) async throws {
        guard let audioLocalPath = meeting.audioLocalPath else {
            return
        }

        let response = try await apiClient.uploadAudio(
            meetingID: meeting.id,
            fileURL: URL(fileURLWithPath: audioLocalPath),
            duration: meeting.audioDuration,
            mimeType: meeting.audioMimeType ?? "audio/m4a"
        )

        meeting.audioRemotePath = apiClient.resolveAbsoluteURLString(response.audioUrl)
        meeting.audioMimeType = response.audioMimeType ?? meeting.audioMimeType
        meeting.audioDuration = response.audioDuration ?? meeting.audioDuration
        meeting.audioUpdatedAt = response.audioUpdatedAt ?? meeting.audioUpdatedAt
    }
}
