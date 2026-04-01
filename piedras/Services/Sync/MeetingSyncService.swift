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
            try await syncRemoteNoteAttachments(for: meeting, remote: remoteMeeting)
            reconcileTranscriptState(for: meeting)
            if let finalizedMeeting = try await uploadLocalAudioIfNeeded(for: meeting) {
                MeetingPayloadMapper.apply(
                    remote: finalizedMeeting,
                    to: meeting,
                    repository: repository,
                    baseURL: apiClient.baseURL
                )
                try await syncRemoteNoteAttachments(for: meeting, remote: finalizedMeeting)
                reconcileTranscriptState(for: meeting)
            }

            if let refreshedMeeting = try await syncNoteAttachmentsIfNeeded(for: meeting) {
                MeetingPayloadMapper.apply(
                    remote: refreshedMeeting,
                    to: meeting,
                    repository: repository,
                    baseURL: apiClient.baseURL
                )
                try await syncRemoteNoteAttachments(for: meeting, remote: refreshedMeeting)
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
        guard meeting.audioCloudSyncEnabled else {
            meeting.audioRemotePath = nil
            return nil
        }

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

    private func syncNoteAttachmentsIfNeeded(for meeting: Meeting) async throws -> RemoteMeetingDetail? {
        try await deletePendingRemoteNoteAttachments(for: meeting)

        let pendingUploads = meeting.noteAttachmentFileNames.filter {
            meeting.noteAttachmentRemoteIDsByFileName[$0]?.isEmpty ?? true
        }

        guard !pendingUploads.isEmpty else {
            return meeting.noteAttachmentPendingDeleteIDs.isEmpty ? nil : try await apiClient.getMeeting(id: meeting.id)
        }

        for fileName in pendingUploads {
            let fileURL = MeetingNoteAttachmentStorage.imageURL(meetingID: meeting.id, fileName: fileName)
            guard FileManager.default.fileExists(atPath: fileURL.path) else { continue }

            let response = try await apiClient.uploadNoteAttachment(
                meetingID: meeting.id,
                fileURL: fileURL,
                mimeType: mimeType(forAttachmentFileName: fileName),
                extractedText: meeting.noteAttachmentExtractedTextByFileName[fileName] ?? ""
            )

            var remoteIDs = meeting.noteAttachmentRemoteIDsByFileName
            remoteIDs[fileName] = response.id
            meeting.noteAttachmentRemoteIDsByFileName = remoteIDs

            if let extractedText = response.extractedText?.trimmingCharacters(in: .whitespacesAndNewlines),
               !extractedText.isEmpty {
                var extractedTexts = meeting.noteAttachmentExtractedTextByFileName
                extractedTexts[fileName] = extractedText
                meeting.noteAttachmentExtractedTextByFileName = extractedTexts
            }
            try repository.save()
        }

        return try await apiClient.getMeeting(id: meeting.id)
    }

    private func deletePendingRemoteNoteAttachments(for meeting: Meeting) async throws {
        let pendingDeleteIDs = meeting.noteAttachmentPendingDeleteIDs
        guard !pendingDeleteIDs.isEmpty else { return }

        var remainingDeleteIDs: [String] = []
        for attachmentID in pendingDeleteIDs {
            do {
                try await apiClient.deleteNoteAttachment(meetingID: meeting.id, attachmentID: attachmentID)
            } catch {
                remainingDeleteIDs.append(attachmentID)
            }
        }

        meeting.noteAttachmentPendingDeleteIDs = remainingDeleteIDs
        try repository.save()
    }

    private func syncRemoteNoteAttachments(
        for meeting: Meeting,
        remote: RemoteMeetingDetail
    ) async throws {
        let remoteAttachments = remote.noteAttachments ?? []
        let remoteIDs = Set(remoteAttachments.map(\.id))
        var fileNames = meeting.noteAttachmentFileNames
        var remoteIDByFileName = meeting.noteAttachmentRemoteIDsByFileName
        var extractedTextByFileName = meeting.noteAttachmentExtractedTextByFileName

        let obsoleteFileNames = fileNames.filter {
            guard let remoteID = remoteIDByFileName[$0] else { return false }
            return !remoteIDs.contains(remoteID)
        }

        for fileName in obsoleteFileNames {
            MeetingNoteAttachmentStorage.deleteImage(meetingID: meeting.id, fileName: fileName)
            remoteIDByFileName.removeValue(forKey: fileName)
            extractedTextByFileName.removeValue(forKey: fileName)
        }

        fileNames.removeAll { obsoleteFileNames.contains($0) }

        for attachment in remoteAttachments {
            if let existingFileName = remoteIDByFileName.first(where: { $0.value == attachment.id })?.key,
               FileManager.default.fileExists(atPath: MeetingNoteAttachmentStorage.imageURL(meetingID: meeting.id, fileName: existingFileName).path) {
                if let extractedText = attachment.extractedText?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !extractedText.isEmpty {
                    extractedTextByFileName[existingFileName] = extractedText
                }
                continue
            }

            let data = try await apiClient.downloadAuthenticatedData(fromAbsoluteURLString: attachment.url)
            let cachedFileName = MeetingNoteAttachmentStorage.cachedFileName(
                remoteAttachmentID: attachment.id,
                mimeType: attachment.mimeType,
                originalName: attachment.originalName
            )
            let localFileName = try MeetingNoteAttachmentStorage.saveData(
                data,
                meetingID: meeting.id,
                preferredFileName: cachedFileName
            )

            if !fileNames.contains(localFileName) {
                fileNames.append(localFileName)
            }
            remoteIDByFileName[localFileName] = attachment.id
            if let extractedText = attachment.extractedText?.trimmingCharacters(in: .whitespacesAndNewlines),
               !extractedText.isEmpty {
                extractedTextByFileName[localFileName] = extractedText
            }
        }

        meeting.noteAttachmentFileNames = fileNames
        meeting.noteAttachmentRemoteIDsByFileName = remoteIDByFileName
        meeting.noteAttachmentExtractedTextByFileName = extractedTextByFileName
        let combinedText = fileNames
            .compactMap { extractedTextByFileName[$0]?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
        if !combinedText.isEmpty || remote.noteAttachmentsTextContext?.isEmpty == false {
            meeting.noteAttachmentTextContext = combinedText.isEmpty ? (remote.noteAttachmentsTextContext ?? "") : combinedText
            meeting.noteAttachmentTextStatus = .ready
            meeting.noteAttachmentTextUpdatedAt = .now
        } else {
            meeting.noteAttachmentTextContext = ""
            meeting.noteAttachmentTextStatus = .idle
            meeting.noteAttachmentTextUpdatedAt = nil
        }
        try repository.save()
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

    private func mimeType(forAttachmentFileName fileName: String) -> String {
        let ext = URL(fileURLWithPath: fileName).pathExtension.lowercased()
        switch ext {
        case "png":
            return "image/png"
        case "heic", "heif":
            return "image/heic"
        default:
            return "image/jpeg"
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
}
