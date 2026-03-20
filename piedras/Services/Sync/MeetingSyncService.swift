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

        guard meeting.status != .transcribing, meeting.status != .transcriptionFailed else {
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

            meeting.syncState = .synced
            meeting.lastSyncedAt = .now
            meeting.updatedAt = .now
            try repository.save()
            try pruneLocalAudioIfNeeded(for: meeting)
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

        guard meeting.audioRemotePath != nil else {
            return
        }

        guard let audioLocalPath = meeting.audioLocalPath else {
            return
        }

        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: audioLocalPath) else {
            meeting.audioLocalPath = nil
            try repository.save()
            return
        }

        try fileManager.removeItem(atPath: audioLocalPath)
        meeting.audioLocalPath = nil
        try repository.save()
    }
}
