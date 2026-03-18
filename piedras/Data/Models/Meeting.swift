import Foundation
import SwiftData

enum MeetingStatus: String, Codable, CaseIterable, Identifiable {
    case idle
    case recording
    case paused
    case ended

    var id: String { rawValue }
}

enum MeetingSyncState: String, Codable, CaseIterable, Identifiable {
    case pending
    case syncing
    case synced
    case failed
    case deleted

    var id: String { rawValue }
}

enum MeetingRecordingMode: String, Codable, CaseIterable, Identifiable {
    case microphone
    case fileMix

    var id: String { rawValue }
}

@Model
final class Meeting {
    @Attribute(.unique) var id: String
    var title: String
    var date: Date
    var statusRaw: String
    var recordingModeRaw: String
    var durationSeconds: Int
    var userNotesPlainText: String
    var enhancedNotes: String
    var audioLocalPath: String?
    var audioRemotePath: String?
    var audioMimeType: String?
    var audioDuration: Int
    var audioUpdatedAt: Date?
    var sourceAudioLocalPath: String?
    var sourceAudioDisplayName: String?
    var sourceAudioDuration: Int
    var hiddenWorkspaceId: String?
    var syncStateRaw: String
    var lastSyncedAt: Date?
    var createdAt: Date
    var updatedAt: Date

    @Relationship(deleteRule: .cascade, inverse: \TranscriptSegment.meeting)
    var segments: [TranscriptSegment]

    @Relationship(deleteRule: .cascade, inverse: \ChatMessage.meeting)
    var chatMessages: [ChatMessage]

    init(
        id: String = UUID().uuidString.lowercased(),
        title: String = "",
        date: Date = .now,
        status: MeetingStatus = .idle,
        recordingMode: MeetingRecordingMode = .microphone,
        durationSeconds: Int = 0,
        userNotesPlainText: String = "",
        enhancedNotes: String = "",
        audioLocalPath: String? = nil,
        audioRemotePath: String? = nil,
        audioMimeType: String? = nil,
        audioDuration: Int = 0,
        audioUpdatedAt: Date? = nil,
        sourceAudioLocalPath: String? = nil,
        sourceAudioDisplayName: String? = nil,
        sourceAudioDuration: Int = 0,
        hiddenWorkspaceId: String? = nil,
        syncState: MeetingSyncState = .pending,
        lastSyncedAt: Date? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        segments: [TranscriptSegment] = [],
        chatMessages: [ChatMessage] = []
    ) {
        self.id = id
        self.title = title
        self.date = date
        self.statusRaw = status.rawValue
        self.recordingModeRaw = recordingMode.rawValue
        self.durationSeconds = durationSeconds
        self.userNotesPlainText = userNotesPlainText
        self.enhancedNotes = enhancedNotes
        self.audioLocalPath = audioLocalPath
        self.audioRemotePath = audioRemotePath
        self.audioMimeType = audioMimeType
        self.audioDuration = audioDuration
        self.audioUpdatedAt = audioUpdatedAt
        self.sourceAudioLocalPath = sourceAudioLocalPath
        self.sourceAudioDisplayName = sourceAudioDisplayName
        self.sourceAudioDuration = sourceAudioDuration
        self.hiddenWorkspaceId = hiddenWorkspaceId
        self.syncStateRaw = syncState.rawValue
        self.lastSyncedAt = lastSyncedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.segments = segments
        self.chatMessages = chatMessages
    }

    var status: MeetingStatus {
        get { MeetingStatus(rawValue: statusRaw) ?? .idle }
        set { statusRaw = newValue.rawValue }
    }

    var recordingMode: MeetingRecordingMode {
        get { MeetingRecordingMode(rawValue: recordingModeRaw) ?? .microphone }
        set { recordingModeRaw = newValue.rawValue }
    }

    var syncState: MeetingSyncState {
        get { MeetingSyncState(rawValue: syncStateRaw) ?? .pending }
        set { syncStateRaw = newValue.rawValue }
    }

    var displayTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "未命名会议" : trimmed
    }

    var orderedSegments: [TranscriptSegment] {
        segments.sorted { lhs, rhs in
            if lhs.orderIndex == rhs.orderIndex {
                return lhs.startTime < rhs.startTime
            }
            return lhs.orderIndex < rhs.orderIndex
        }
    }

    var orderedChatMessages: [ChatMessage] {
        chatMessages.sorted { lhs, rhs in
            if lhs.orderIndex == rhs.orderIndex {
                return lhs.timestamp < rhs.timestamp
            }
            return lhs.orderIndex < rhs.orderIndex
        }
    }

    var transcriptText: String {
        orderedSegments.map(\.text).joined(separator: "\n")
    }

    var searchIndexText: String {
        [title, userNotesPlainText, enhancedNotes, transcriptText, sourceAudioDisplayName ?? ""]
            .joined(separator: "\n")
            .lowercased()
    }

    func markPending() {
        updatedAt = .now
        if syncState != .syncing {
            syncState = .pending
        }
    }
}
