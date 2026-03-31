import Foundation

struct RemoteWorkspace: Codable, Equatable {
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

struct RemoteBackendHealth: Decodable {
    let ok: Bool?
    let database: Bool?
    let asr: RemoteASRStatus?
    let llm: RemoteLLMStatus?
    let startupBootstrap: RemoteStartupBootstrapStatus?
    let checkedAt: Date?
}

struct RemoteStartupBootstrapStatus: Decodable {
    let ready: Bool
    let status: String
    let attempts: Int
    let startedAt: Date?
    let completedAt: Date?
    let lastError: String?
    let schemaReady: Bool
    let missingItems: [String]
    let legacyUsers: [String]
    let retryScheduled: Bool
    let retryAt: Date?
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
    let meetingId: String?
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
    let audioEnhancedNotes: String?
    let audioEnhancedNotesStatus: String?
    let audioEnhancedNotesError: String?
    let audioEnhancedNotesUpdatedAt: Date?
    let audioEnhancedNotesProvider: String?
    let audioEnhancedNotesModel: String?
    let createdAt: Date?
    let updatedAt: Date?
    let workspaceId: String?
    let speakers: [String: String]?
    let segments: [RemoteTranscriptSegment]
    let chatMessages: [RemoteChatMessage]
    let hasAudio: Bool?
    let audioUrl: String?
    let audioProcessingState: String?
    let audioProcessingError: String?
    let audioProcessingAttempts: Int?
    let audioProcessingRequestedAt: Date?
    let audioProcessingStartedAt: Date?
    let audioProcessingCompletedAt: Date?

    init(
        id: String,
        title: String?,
        date: Date,
        status: String?,
        duration: Int?,
        audioMimeType: String?,
        audioDuration: Int?,
        audioUpdatedAt: Date?,
        userNotes: String?,
        enhancedNotes: String?,
        audioEnhancedNotes: String? = nil,
        audioEnhancedNotesStatus: String? = nil,
        audioEnhancedNotesError: String? = nil,
        audioEnhancedNotesUpdatedAt: Date? = nil,
        audioEnhancedNotesProvider: String? = nil,
        audioEnhancedNotesModel: String? = nil,
        createdAt: Date?,
        updatedAt: Date?,
        workspaceId: String?,
        speakers: [String: String]? = nil,
        segments: [RemoteTranscriptSegment],
        chatMessages: [RemoteChatMessage],
        hasAudio: Bool?,
        audioUrl: String?,
        audioProcessingState: String? = nil,
        audioProcessingError: String? = nil,
        audioProcessingAttempts: Int? = nil,
        audioProcessingRequestedAt: Date? = nil,
        audioProcessingStartedAt: Date? = nil,
        audioProcessingCompletedAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.date = date
        self.status = status
        self.duration = duration
        self.audioMimeType = audioMimeType
        self.audioDuration = audioDuration
        self.audioUpdatedAt = audioUpdatedAt
        self.userNotes = userNotes
        self.enhancedNotes = enhancedNotes
        self.audioEnhancedNotes = audioEnhancedNotes
        self.audioEnhancedNotesStatus = audioEnhancedNotesStatus
        self.audioEnhancedNotesError = audioEnhancedNotesError
        self.audioEnhancedNotesUpdatedAt = audioEnhancedNotesUpdatedAt
        self.audioEnhancedNotesProvider = audioEnhancedNotesProvider
        self.audioEnhancedNotesModel = audioEnhancedNotesModel
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.workspaceId = workspaceId
        self.speakers = speakers
        self.segments = segments
        self.chatMessages = chatMessages
        self.hasAudio = hasAudio
        self.audioUrl = audioUrl
        self.audioProcessingState = audioProcessingState
        self.audioProcessingError = audioProcessingError
        self.audioProcessingAttempts = audioProcessingAttempts
        self.audioProcessingRequestedAt = audioProcessingRequestedAt
        self.audioProcessingStartedAt = audioProcessingStartedAt
        self.audioProcessingCompletedAt = audioProcessingCompletedAt
    }
}

struct RemoteAudioUploadResponse: Decodable {
    let hasAudio: Bool
    let audioMimeType: String?
    let audioDuration: Int?
    let audioUpdatedAt: Date?
    let audioUrl: String?
    let audioProcessingState: String?
    let audioProcessingError: String?
    let audioProcessingAttempts: Int?
    let audioProcessingRequestedAt: Date?
    let audioProcessingStartedAt: Date?
    let audioProcessingCompletedAt: Date?
}

struct RemoteMeetingProcessingStatus: Decodable {
    let meetingId: String
    let hasAudio: Bool
    let audioProcessingState: String?
    let audioProcessingError: String?
    let audioProcessingAttempts: Int?
    let audioProcessingRequestedAt: Date?
    let audioProcessingStartedAt: Date?
    let audioProcessingCompletedAt: Date?
}

struct RemoteEnhanceResponse: Decodable {
    let content: String
    let provider: String?
}

struct RemoteAudioEnhanceResponse: Decodable {
    let content: String?
    let provider: String?
    let model: String?
    let status: String?
    let updatedAt: Date?
}

struct RemoteAudioEnhanceStatusResponse: Decodable {
    let meetingId: String
    let hasAudio: Bool
    let audioEnhancedNotes: String
    let audioEnhancedNotesStatus: String
    let audioEnhancedNotesError: String?
    let audioEnhancedNotesUpdatedAt: Date?
    let audioEnhancedNotesProvider: String?
    let audioEnhancedNotesModel: String?
    let audioEnhancedNotesAttempts: Int
    let audioEnhancedNotesRequestedAt: Date?
    let audioEnhancedNotesStartedAt: Date?
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
    let segmentCommentsContext: String
    let noteAttachmentsContext: String
    let promptOptions: PromptOptions?
}

struct AudioEnhanceRequestPayload: Encodable {
    let userNotes: String
    let noteAttachmentsContext: String
    let segmentCommentsContext: String
    let promptOptions: PromptOptions?
}

struct PromptOptions: Encodable {
    let meetingType: String
    let outputStyle: String
    let includeActionItems: Bool
}

struct ChatHistoryPayload: Encodable {
    let role: String
    let content: String
}

struct ChatRequestPayload: Encodable {
    let transcript: String
    let userNotes: String
    let enhancedNotes: String
    let noteAttachmentsContext: String
    let segmentCommentsContext: String
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
    let localRetrievalContext: String?
    let localRetrievalSources: [LocalMeetingRetrievalSource]?
    let localCommentContext: String?
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
            speakers: meeting.speakers,
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
            meetingTitle: meeting.displayTitle,
            segmentCommentsContext: MeetingCommentContextBuilder.segmentCommentsContext(for: meeting),
            noteAttachmentsContext: MeetingCommentContextBuilder.noteAttachmentsContext(for: meeting),
            promptOptions: PromptOptions(
                meetingType: meeting.meetingType,
                outputStyle: "平衡",
                includeActionItems: true
            )
        )
    }

    static func makeAudioEnhancePayload(from meeting: Meeting) -> AudioEnhanceRequestPayload {
        AudioEnhanceRequestPayload(
            userNotes: meeting.userNotesPlainText,
            noteAttachmentsContext: MeetingCommentContextBuilder.noteAttachmentsContext(for: meeting),
            segmentCommentsContext: MeetingCommentContextBuilder.segmentCommentsContext(for: meeting),
            promptOptions: PromptOptions(
                meetingType: meeting.meetingType,
                outputStyle: "平衡",
                includeActionItems: true
            )
        )
    }

    static func makeChatPayload(from meeting: Meeting, history: [ChatMessage], question: String) -> ChatRequestPayload {
        ChatRequestPayload(
            transcript: transcriptText(from: meeting),
            userNotes: meeting.userNotesPlainText,
            enhancedNotes: meeting.enhancedNotes,
            noteAttachmentsContext: MeetingCommentContextBuilder.noteAttachmentsContext(for: meeting),
            segmentCommentsContext: MeetingCommentContextBuilder.segmentCommentsContext(for: meeting),
            chatHistory: history.suffix(10).map {
                ChatHistoryPayload(role: $0.role, content: $0.content)
            },
            question: question
        )
    }

    static func makeChatPayload(from meeting: Meeting, question: String) -> ChatRequestPayload {
        makeChatPayload(
            from: meeting,
            history: meeting.orderedChatMessages,
            question: question
        )
    }

    static func makeChatPayload(from meeting: Meeting, session: ChatSession, question: String) -> ChatRequestPayload {
        makeChatPayload(
            from: meeting,
            history: session.orderedMessages,
            question: question
        )
    }

    static func makeMeeting(from remote: RemoteMeetingDetail, baseURL: URL?) -> Meeting {
        let status = mapStatus(remote.status)
        let meeting = Meeting(
            id: remote.id,
            title: remote.title ?? "",
            date: remote.date,
            status: status,
            durationSeconds: remote.duration ?? 0,
            userNotesPlainText: PlainTextHTMLAdapter.plainText(from: remote.userNotes ?? ""),
            enhancedNotes: remote.enhancedNotes ?? "",
            audioEnhancedNotes: remote.audioEnhancedNotes ?? "",
            audioEnhancedNotesStatus: AudioEnhancedNotesStatus(rawValue: remote.audioEnhancedNotesStatus ?? "") ?? .idle,
            audioEnhancedNotesError: remote.audioEnhancedNotesError ?? "",
            audioEnhancedNotesUpdatedAt: remote.audioEnhancedNotesUpdatedAt,
            audioEnhancedNotesProvider: remote.audioEnhancedNotesProvider,
            audioEnhancedNotesModel: remote.audioEnhancedNotesModel,
            audioLocalPath: nil,
            audioRemotePath: resolveRemoteAudioURLString(from: remote.audioUrl, baseURL: baseURL),
            audioMimeType: remote.audioMimeType,
            audioDuration: remote.audioDuration ?? 0,
            audioUpdatedAt: remote.audioUpdatedAt,
            hiddenWorkspaceId: remote.workspaceId,
            speakers: remote.speakers ?? [:],
            transcriptPipelineState: status == .ended ? .ready : (status == .transcriptionFailed ? .failed : .idle),
            syncState: .synced,
            lastSyncedAt: .now,
            createdAt: remote.createdAt ?? remote.date,
            updatedAt: remote.updatedAt ?? .now,
            segments: makeSegments(from: remote.segments),
            chatMessages: makeChatMessages(from: remote.chatMessages)
        )
        applyRemoteAudioProcessing(remote, to: meeting)
        return meeting
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
        meeting.durationSeconds = remote.duration ?? meeting.durationSeconds
        meeting.userNotesPlainText = PlainTextHTMLAdapter.plainText(from: remote.userNotes ?? "")
        meeting.enhancedNotes = remote.enhancedNotes ?? ""
        meeting.audioEnhancedNotes = remote.audioEnhancedNotes ?? ""
        meeting.audioEnhancedNotesStatus = AudioEnhancedNotesStatus(rawValue: remote.audioEnhancedNotesStatus ?? "") ?? .idle
        meeting.audioEnhancedNotesError = remote.audioEnhancedNotesError ?? ""
        meeting.audioEnhancedNotesUpdatedAt = remote.audioEnhancedNotesUpdatedAt
        meeting.audioEnhancedNotesProvider = remote.audioEnhancedNotesProvider
        meeting.audioEnhancedNotesModel = remote.audioEnhancedNotesModel
        meeting.audioRemotePath = resolveRemoteAudioURLString(from: remote.audioUrl, baseURL: baseURL)
        meeting.audioMimeType = remote.audioMimeType ?? meeting.audioMimeType
        meeting.audioDuration = remote.audioDuration ?? meeting.audioDuration
        meeting.audioUpdatedAt = remote.audioUpdatedAt ?? meeting.audioUpdatedAt
        meeting.hiddenWorkspaceId = remote.workspaceId ?? meeting.hiddenWorkspaceId
        meeting.speakers = remote.speakers ?? meeting.speakers
        meeting.syncState = .synced
        meeting.lastSyncedAt = .now
        meeting.createdAt = remote.createdAt ?? meeting.createdAt
        meeting.updatedAt = remote.updatedAt ?? .now
        applyRemoteAudioProcessing(remote, to: meeting)

        repository.replaceSegments(for: meeting, with: makeSegments(from: remote.segments))
        let remoteChatMessages = makeChatMessages(from: remote.chatMessages)

        if meeting.chatSessions.isEmpty {
            repository.replaceChatMessages(for: meeting, with: remoteChatMessages)
            return
        }

        guard let onlySession = meeting.chatSessions.only else {
            return
        }

        guard !remoteChatMessages.isEmpty else {
            return
        }

        repository.replaceChatMessages(for: meeting, in: onlySession, with: remoteChatMessages)
        if let title = remoteChatMessages.first(where: { $0.role == "user" })?.content
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !title.isEmpty {
            onlySession.title = title
        }
        if let firstTimestamp = remoteChatMessages.first?.timestamp {
            onlySession.createdAt = firstTimestamp
        }
        if let lastTimestamp = remoteChatMessages.last?.timestamp {
            onlySession.updatedAt = lastTimestamp
        }
    }

    static func apply(
        processingStatus remote: RemoteMeetingProcessingStatus,
        to meeting: Meeting
    ) {
        applyRemoteAudioProcessing(
            audioProcessingState: remote.audioProcessingState,
            audioProcessingError: remote.audioProcessingError,
            to: meeting
        )
    }

    static func apply(
        audioEnhanceStatus remote: RemoteAudioEnhanceStatusResponse,
        to meeting: Meeting
    ) {
        meeting.audioEnhancedNotes = remote.audioEnhancedNotes
        meeting.audioEnhancedNotesStatus = AudioEnhancedNotesStatus(rawValue: remote.audioEnhancedNotesStatus) ?? .idle
        meeting.audioEnhancedNotesError = remote.audioEnhancedNotesError ?? ""
        meeting.audioEnhancedNotesUpdatedAt = remote.audioEnhancedNotesUpdatedAt
        meeting.audioEnhancedNotesProvider = remote.audioEnhancedNotesProvider
        meeting.audioEnhancedNotesModel = remote.audioEnhancedNotesModel
    }

    static func transcriptText(from meeting: Meeting) -> String {
        let finalSegments = meeting.orderedSegments.filter(\.isFinal)
        let source = finalSegments.isEmpty ? meeting.orderedSegments : finalSegments
        return source
            .map { "[\(meeting.displayName(forSpeaker: $0.speaker))]: \($0.text)" }
            .joined(separator: "\n")
    }

    private static func applyRemoteAudioProcessing(
        _ remote: RemoteMeetingDetail,
        to meeting: Meeting
    ) {
        applyRemoteAudioProcessing(
            audioProcessingState: remote.audioProcessingState,
            audioProcessingError: remote.audioProcessingError,
            to: meeting
        )
    }

    private static func applyRemoteAudioProcessing(
        audioProcessingState: String?,
        audioProcessingError: String?,
        to meeting: Meeting
    ) {
        switch audioProcessingState {
        case "queued", "processing":
            meeting.speakerDiarizationState = .processing
            meeting.speakerDiarizationErrorMessage = nil
            if meeting.status == .ended {
                meeting.transcriptPipelineState = .refining
            }
        case "failed":
            meeting.speakerDiarizationState = .failed
            let errorMessage = audioProcessingError?.trimmingCharacters(in: .whitespacesAndNewlines)
            meeting.speakerDiarizationErrorMessage = (errorMessage?.isEmpty == false) ? errorMessage : nil
            meeting.transcriptPipelineState = .failed
        case "completed":
            meeting.speakerDiarizationState = .ready
            meeting.speakerDiarizationErrorMessage = nil
            if meeting.status == .ended {
                meeting.transcriptPipelineState = .ready
            }
        default:
            break
        }
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

private extension Collection {
    var only: Element? {
        count == 1 ? first : nil
    }
}
