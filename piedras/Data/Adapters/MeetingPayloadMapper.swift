import Foundation

struct RemoteWorkspace: Decodable {
    let id: String
    let name: String
}

struct RemoteASRStatus: Decodable {
    let mode: String
    let provider: String
    let configured: Bool?
    let reachable: Bool?
    let ready: Bool
    let missing: [String]
    let message: String
    let checkedAt: Date?
    let lastError: String?
}

struct RemoteLLMStatus: Decodable {
    let configured: Bool?
    let reachable: Bool?
    let ready: Bool
    let provider: String
    let model: String?
    let preset: String?
    let message: String
    let checkedAt: Date?
    let lastError: String?
}

struct RemoteASRSession: Decodable {
    let wsUrl: String
    let token: String?
    let tokenExpireTime: Int?
    let appKey: String?
    let vocabularyId: String?
    let sampleRate: Int?
    let channels: Int?
    let codec: String?
    let packetDurationMs: Int?
}

struct RemoteASRSessionResponse: Decodable {
    let session: RemoteASRSession?
    let error: String?
}

struct ASRSessionRequestPayload: Encodable {
    let sampleRate: Int
    let channels: Int
    let workspaceId: String?
}

struct RemoteMeetingListItem: Decodable {
    let id: String
}

struct RemoteTranscriptSegment: Decodable {
    let id: String
    let speaker: String
    let text: String
    let startTime: Double
    let endTime: Double
    let isFinal: Bool
    let order: Int?
}

struct RemoteChatMessage: Decodable {
    let id: String
    let role: String
    let content: String
    let timestamp: Date
}

struct RemoteMeetingDetail: Decodable {
    let id: String
    let title: String?
    let date: Date
    let status: String?
    let duration: Int?
    let audioMimeType: String?
    let audioDuration: Int?
    let audioUpdatedAt: Date?
    let userNotes: String?
    let enhancedNotes: String?
    let createdAt: Date?
    let updatedAt: Date?
    let workspaceId: String?
    let segments: [RemoteTranscriptSegment]
    let chatMessages: [RemoteChatMessage]
    let hasAudio: Bool?
    let audioUrl: String?
}

struct RemoteAudioUploadResponse: Decodable {
    let hasAudio: Bool
    let audioMimeType: String?
    let audioDuration: Int?
    let audioUpdatedAt: Date?
    let audioUrl: String?
}

struct RemoteEnhanceResponse: Decodable {
    let content: String
    let provider: String?
}

struct RemoteMeetingTitleResponse: Decodable {
    let title: String
    let provider: String?
}

struct WorkspaceCreatePayload: Encodable {
    let name: String
    let description: String
    let icon: String
    let color: String
    let workflowMode: String
    let modeLabel: String
}

struct MeetingSegmentPayload: Encodable {
    let id: String
    let speaker: String
    let text: String
    let startTime: Double
    let endTime: Double
    let isFinal: Bool
}

struct MeetingChatMessagePayload: Encodable {
    let id: String
    let role: String
    let content: String
    let timestamp: Int64
}

struct MeetingUpsertPayload: Encodable {
    let id: String
    let title: String
    let date: String
    let status: String
    let duration: Int
    let workspaceId: String
    let userNotes: String
    let enhancedNotes: String
    let speakers: [String: String]
    let segments: [MeetingSegmentPayload]
    let chatMessages: [MeetingChatMessagePayload]
}

struct EnhanceRequestPayload: Encodable {
    let transcript: String
    let userNotes: String
    let meetingTitle: String
}

struct ChatHistoryPayload: Encodable {
    let role: String
    let content: String
}

struct ChatRequestPayload: Encodable {
    let transcript: String
    let userNotes: String
    let enhancedNotes: String
    let chatHistory: [ChatHistoryPayload]
    let question: String
}

struct GlobalChatFiltersPayload: Encodable {
    let workspaceId: String?
}

struct GlobalChatRequestPayload: Encodable {
    let question: String
    let chatHistory: [ChatHistoryPayload]
    let filters: GlobalChatFiltersPayload?
}

enum MeetingPayloadMapper {
    private static let iso8601FormatterWithFractionalSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static func makeMeetingUpsertPayload(from meeting: Meeting, workspaceID: String) -> MeetingUpsertPayload {
        MeetingUpsertPayload(
            id: meeting.id,
            title: meeting.title,
            date: iso8601FormatterWithFractionalSeconds.string(from: meeting.date),
            status: meeting.status.rawValue,
            duration: meeting.durationSeconds,
            workspaceId: workspaceID,
            userNotes: PlainTextHTMLAdapter.html(from: meeting.userNotesPlainText),
            enhancedNotes: meeting.enhancedNotes,
            speakers: [:],
            segments: meeting.orderedSegments.map {
                MeetingSegmentPayload(
                    id: $0.id,
                    speaker: $0.speaker,
                    text: $0.text,
                    startTime: $0.startTime,
                    endTime: $0.endTime,
                    isFinal: $0.isFinal
                )
            },
            chatMessages: meeting.orderedChatMessages.map {
                MeetingChatMessagePayload(
                    id: $0.id,
                    role: $0.role,
                    content: $0.content,
                    timestamp: Int64(($0.timestamp.timeIntervalSince1970 * 1000).rounded())
                )
            }
        )
    }

    static func makeEnhancePayload(from meeting: Meeting) -> EnhanceRequestPayload {
        EnhanceRequestPayload(
            transcript: transcriptText(from: meeting),
            userNotes: meeting.userNotesPlainText,
            meetingTitle: meeting.displayTitle
        )
    }

    static func makeChatPayload(from meeting: Meeting, question: String) -> ChatRequestPayload {
        ChatRequestPayload(
            transcript: transcriptText(from: meeting),
            userNotes: meeting.userNotesPlainText,
            enhancedNotes: meeting.enhancedNotes,
            chatHistory: meeting.orderedChatMessages.suffix(10).map {
                ChatHistoryPayload(role: $0.role, content: $0.content)
            },
            question: question
        )
    }

    static func makeMeeting(from remote: RemoteMeetingDetail, baseURL: URL?) -> Meeting {
        Meeting(
            id: remote.id,
            title: remote.title ?? "",
            date: remote.date,
            status: mapStatus(remote.status),
            durationSeconds: remote.duration ?? 0,
            userNotesPlainText: PlainTextHTMLAdapter.plainText(from: remote.userNotes ?? ""),
            enhancedNotes: remote.enhancedNotes ?? "",
            audioLocalPath: nil,
            audioRemotePath: resolveRemoteAudioURLString(from: remote.audioUrl, baseURL: baseURL),
            audioMimeType: remote.audioMimeType,
            audioDuration: remote.audioDuration ?? 0,
            audioUpdatedAt: remote.audioUpdatedAt,
            hiddenWorkspaceId: remote.workspaceId,
            syncState: .synced,
            lastSyncedAt: .now,
            createdAt: remote.createdAt ?? remote.date,
            updatedAt: remote.updatedAt ?? .now,
            segments: makeSegments(from: remote.segments),
            chatMessages: makeChatMessages(from: remote.chatMessages)
        )
    }

    static func apply(
        remote: RemoteMeetingDetail,
        to meeting: Meeting,
        repository: MeetingRepository,
        baseURL: URL?
    ) {
        meeting.title = remote.title ?? ""
        meeting.date = remote.date
        meeting.status = mapStatus(remote.status)
        meeting.durationSeconds = remote.duration ?? meeting.durationSeconds
        meeting.userNotesPlainText = PlainTextHTMLAdapter.plainText(from: remote.userNotes ?? "")
        meeting.enhancedNotes = remote.enhancedNotes ?? ""
        meeting.audioRemotePath = resolveRemoteAudioURLString(from: remote.audioUrl, baseURL: baseURL)
        meeting.audioMimeType = remote.audioMimeType ?? meeting.audioMimeType
        meeting.audioDuration = remote.audioDuration ?? meeting.audioDuration
        meeting.audioUpdatedAt = remote.audioUpdatedAt ?? meeting.audioUpdatedAt
        meeting.hiddenWorkspaceId = remote.workspaceId ?? meeting.hiddenWorkspaceId
        meeting.syncState = .synced
        meeting.lastSyncedAt = .now
        meeting.createdAt = remote.createdAt ?? meeting.createdAt
        meeting.updatedAt = remote.updatedAt ?? .now

        repository.replaceSegments(for: meeting, with: makeSegments(from: remote.segments))
        repository.replaceChatMessages(for: meeting, with: makeChatMessages(from: remote.chatMessages))
    }

    static func transcriptText(from meeting: Meeting) -> String {
        let finalSegments = meeting.orderedSegments.filter(\.isFinal)
        let source = finalSegments.isEmpty ? meeting.orderedSegments : finalSegments
        return source
            .map { "[\($0.speaker)]: \($0.text)" }
            .joined(separator: "\n")
    }

    private static func makeSegments(from remoteSegments: [RemoteTranscriptSegment]) -> [TranscriptSegment] {
        remoteSegments.enumerated().map { index, remoteSegment in
            TranscriptSegment(
                id: remoteSegment.id,
                speaker: remoteSegment.speaker,
                text: remoteSegment.text,
                startTime: remoteSegment.startTime,
                endTime: remoteSegment.endTime,
                isFinal: remoteSegment.isFinal,
                orderIndex: remoteSegment.order ?? index
            )
        }
    }

    private static func makeChatMessages(from remoteMessages: [RemoteChatMessage]) -> [ChatMessage] {
        remoteMessages.enumerated().map { index, remoteMessage in
            ChatMessage(
                id: remoteMessage.id,
                role: remoteMessage.role,
                content: remoteMessage.content,
                timestamp: remoteMessage.timestamp,
                orderIndex: index
            )
        }
    }

    private static func mapStatus(_ rawValue: String?) -> MeetingStatus {
        MeetingStatus(rawValue: rawValue ?? "") ?? .ended
    }

    private static func resolveRemoteAudioURLString(from path: String?, baseURL: URL?) -> String? {
        guard let path, !path.isEmpty else {
            return nil
        }

        if URL(string: path)?.scheme != nil {
            return path
        }

        guard let baseURL else {
            return path
        }

        return URL(string: path, relativeTo: baseURL)?.absoluteURL.absoluteString ?? path
    }
}
