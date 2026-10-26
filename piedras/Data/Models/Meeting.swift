import CryptoKit
import Foundation
import SwiftData

enum MeetingStatus: String, Codable, CaseIterable, Identifiable {
    case idle
    case recording
    case paused
    case transcribing
    case transcriptionFailed
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

enum MeetingTypeOption: String, CaseIterable, Identifiable {
    case general = "通用"
    case interview = "访谈"
    case speech = "演讲"
    case brainstorming = "头脑风暴"
    case weekly = "项目周会"
    case requirementsReview = "需求评审"
    case sales = "销售沟通"
    case interviewReview = "面试复盘"

    var id: String { rawValue }
}

enum SpeakerDiarizationState: String, Codable, CaseIterable, Identifiable {
    case idle
    case processing
    case ready
    case failed

    var id: String { rawValue }
}

enum TranscriptPipelineState: String, Codable, CaseIterable, Identifiable {
    case idle
    case initializing
    case refining
    case ready
    case failed

    var id: String { rawValue }
}

enum AINotesFreshnessState: String, Codable, CaseIterable, Identifiable {
    case fresh
    case staleFromTranscript
    case staleFromAttachments
    case staleFromTranscriptAndAttachments

    var id: String { rawValue }

    var includesTranscriptChanges: Bool {
        switch self {
        case .fresh, .staleFromAttachments:
            return false
        case .staleFromTranscript, .staleFromTranscriptAndAttachments:
            return true
        }
    }

    var includesAttachmentChanges: Bool {
        switch self {
        case .fresh, .staleFromTranscript:
            return false
        case .staleFromAttachments, .staleFromTranscriptAndAttachments:
            return true
        }
    }

    func settingTranscriptChanges(_ includesTranscriptChanges: Bool) -> Self {
        switch (includesTranscriptChanges, includesAttachmentChanges) {
        case (false, false):
            return .fresh
        case (true, false):
            return .staleFromTranscript
        case (false, true):
            return .staleFromAttachments
        case (true, true):
            return .staleFromTranscriptAndAttachments
        }
    }

    func settingAttachmentChanges(_ includesAttachmentChanges: Bool) -> Self {
        switch (includesTranscriptChanges, includesAttachmentChanges) {
        case (false, false):
            return .fresh
        case (true, false):
            return .staleFromTranscript
        case (false, true):
            return .staleFromAttachments
        case (true, true):
            return .staleFromTranscriptAndAttachments
        }
    }
}

enum AudioEnhancedNotesStatus: String, Codable, CaseIterable, Identifiable {
    case idle
    case processing
    case ready
    case failed

    var id: String { rawValue }
}

enum MeetingPostStopProcessingStage: String, Codable, CaseIterable, Identifiable {
    case idle
    case repairingTranscript
    case finalizing

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
    @Attribute(originalName: "audioEnhancedNotes")
    private var audioEnhancedNotesValue: String?
    @Attribute(originalName: "audioEnhancedNotesStatusRawValue")
    private var audioEnhancedNotesStatusRawValueValue: String?
    @Attribute(originalName: "postStopProcessingStageRawValue")
    private var postStopProcessingStageRawValueValue: String?
    @Attribute(originalName: "audioEnhancedNotesError")
    private var audioEnhancedNotesErrorValue: String?
    var audioEnhancedNotesUpdatedAt: Date?
    var audioEnhancedNotesProvider: String?
    var audioEnhancedNotesModel: String?
    @Attribute(originalName: "noteAttachmentFileNames")
    private var noteAttachmentFileNamesValue: [String]?
    @Attribute(originalName: "noteAttachmentAssetIdentifiersRaw")
    private var noteAttachmentAssetIdentifiersRawValue: String?
    @Attribute(originalName: "noteAttachmentRemoteIDsRaw")
    private var noteAttachmentRemoteIDsRawValue: String?
    @Attribute(originalName: "noteAttachmentExtractedTextsRaw")
    private var noteAttachmentExtractedTextsRawValue: String?
    @Attribute(originalName: "noteAttachmentPendingDeleteIDsRaw")
    private var noteAttachmentPendingDeleteIDsRawValue: String?
    @Attribute(originalName: "noteAttachmentTextContext")
    private var noteAttachmentTextContextValue: String?
    @Attribute(originalName: "noteAttachmentTextStatusRaw")
    private var noteAttachmentTextStatusRawValue: String?
    var noteAttachmentTextUpdatedAt: Date?
    private var audioCloudSyncEnabledValue: Bool?
    var audioLocalPath: String?
    var audioRemotePath: String?
    var audioMimeType: String?
    var audioDuration: Int
    var audioUpdatedAt: Date?
    var sourceAudioLocalPath: String?
    var sourceAudioDisplayName: String?
    var sourceAudioDuration: Int
    var hiddenWorkspaceId: String?
    var collectionId: String?
    var previousCollectionId: String?
    var deletedAt: Date?
    @Attribute(originalName: "speakersRaw")
    private var speakersRawValue: String?
    @Attribute(originalName: "speakerDiarizationStateRaw")
    private var speakerDiarizationStateRawValue: String?
    var speakerDiarizationErrorMessage: String?
    private var transcriptPipelineStateRawValue: String?
    var syncStateRaw: String
    @Attribute(originalName: "meetingTypeRaw")
    private var meetingTypeRawValue: String?
    var lastSyncedAt: Date?
    private var aiNotesFreshnessStateRawValue: String?
    var lastAINotesTranscriptFingerprint: String?
    @Attribute(originalName: "hasPendingImageTextRefresh")
    private var hasPendingImageTextRefreshValue: Bool?
    var createdAt: Date
    var updatedAt: Date

    @Relationship(deleteRule: .cascade, inverse: \TranscriptSegment.meeting)
    var segments: [TranscriptSegment]

    @Relationship(deleteRule: .cascade, inverse: \ChatMessage.meeting)
    var chatMessages: [ChatMessage]

    @Relationship(deleteRule: .cascade, inverse: \ChatSession.meeting)
    var chatSessions: [ChatSession]

    init(
        id: String = UUID().uuidString.lowercased(),
        title: String = "",
        date: Date = .now,
        status: MeetingStatus = .idle,
        recordingMode: MeetingRecordingMode = .microphone,
        durationSeconds: Int = 0,
        userNotesPlainText: String = "",
        enhancedNotes: String = "",
        audioEnhancedNotes: String = "",
        audioEnhancedNotesStatus: AudioEnhancedNotesStatus = .idle,
        postStopProcessingStage: MeetingPostStopProcessingStage = .idle,
        audioEnhancedNotesError: String = "",
        audioEnhancedNotesUpdatedAt: Date? = nil,
        audioEnhancedNotesProvider: String? = nil,
        audioEnhancedNotesModel: String? = nil,
        noteAttachmentFileNames: [String] = [],
        noteAttachmentAssetIdentifiersByFileName: [String: String] = [:],
        noteAttachmentRemoteIDsByFileName: [String: String] = [:],
        noteAttachmentExtractedTextByFileName: [String: String] = [:],
        noteAttachmentPendingDeleteIDs: [String] = [],
        noteAttachmentTextContext: String = "",
        noteAttachmentTextStatus: AnnotationImageTextStatus = .idle,
        noteAttachmentTextUpdatedAt: Date? = nil,
        audioCloudSyncEnabled: Bool = true,
        audioLocalPath: String? = nil,
        audioRemotePath: String? = nil,
        audioMimeType: String? = nil,
        audioDuration: Int = 0,
        audioUpdatedAt: Date? = nil,
        sourceAudioLocalPath: String? = nil,
        sourceAudioDisplayName: String? = nil,
        sourceAudioDuration: Int = 0,
        hiddenWorkspaceId: String? = nil,
        collectionId: String? = nil,
        previousCollectionId: String? = nil,
        deletedAt: Date? = nil,
        speakers: [String: String] = [:],
        speakerDiarizationState: SpeakerDiarizationState = .idle,
        speakerDiarizationErrorMessage: String? = nil,
        transcriptPipelineState: TranscriptPipelineState = .idle,
        syncState: MeetingSyncState = .pending,
        meetingType: String = MeetingTypeOption.general.rawValue,
        lastSyncedAt: Date? = nil,
        aiNotesFreshnessState: AINotesFreshnessState = .fresh,
        lastAINotesTranscriptFingerprint: String? = nil,
        hasPendingImageTextRefresh: Bool = false,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        segments: [TranscriptSegment] = [],
        chatMessages: [ChatMessage] = [],
        chatSessions: [ChatSession] = []
    ) {
        self.id = id
        self.title = title
        self.date = date
        self.statusRaw = status.rawValue
        self.recordingModeRaw = recordingMode.rawValue
        self.durationSeconds = durationSeconds
        self.userNotesPlainText = userNotesPlainText
        self.enhancedNotes = enhancedNotes
        self.audioEnhancedNotesValue = audioEnhancedNotes
        self.audioEnhancedNotesStatusRawValueValue = audioEnhancedNotesStatus.rawValue
        self.postStopProcessingStageRawValueValue = postStopProcessingStage.rawValue
        self.audioEnhancedNotesErrorValue = audioEnhancedNotesError
        self.audioEnhancedNotesUpdatedAt = audioEnhancedNotesUpdatedAt
        self.audioEnhancedNotesProvider = audioEnhancedNotesProvider
        self.audioEnhancedNotesModel = audioEnhancedNotesModel
        self.noteAttachmentFileNamesValue = noteAttachmentFileNames
        self.noteAttachmentAssetIdentifiersRawValue = Self.encodeAttachmentAssetIdentifiers(
            noteAttachmentAssetIdentifiersByFileName
        )
        self.noteAttachmentRemoteIDsRawValue = Self.encodeAttachmentAssetIdentifiers(
            noteAttachmentRemoteIDsByFileName
        )
        self.noteAttachmentExtractedTextsRawValue = Self.encodeAttachmentAssetIdentifiers(
            noteAttachmentExtractedTextByFileName
        )
        self.noteAttachmentPendingDeleteIDsRawValue = Self.encodeStringArray(noteAttachmentPendingDeleteIDs)
        self.noteAttachmentTextContextValue = noteAttachmentTextContext
        self.noteAttachmentTextStatusRawValue = noteAttachmentTextStatus.rawValue
        self.noteAttachmentTextUpdatedAt = noteAttachmentTextUpdatedAt
        self.audioCloudSyncEnabledValue = audioCloudSyncEnabled
        self.audioLocalPath = audioLocalPath
        self.audioRemotePath = audioRemotePath
        self.audioMimeType = audioMimeType
        self.audioDuration = audioDuration
        self.audioUpdatedAt = audioUpdatedAt
        self.sourceAudioLocalPath = sourceAudioLocalPath
        self.sourceAudioDisplayName = sourceAudioDisplayName
        self.sourceAudioDuration = sourceAudioDuration
        self.hiddenWorkspaceId = hiddenWorkspaceId
        self.collectionId = collectionId
        self.previousCollectionId = previousCollectionId
        self.deletedAt = deletedAt
        self.speakersRawValue = Self.encodeSpeakers(speakers)
        self.speakerDiarizationStateRawValue = speakerDiarizationState.rawValue
        self.speakerDiarizationErrorMessage = speakerDiarizationErrorMessage
        self.transcriptPipelineStateRawValue = transcriptPipelineState.rawValue
        self.syncStateRaw = syncState.rawValue
        self.meetingTypeRawValue = Self.normalizedMeetingTypeRaw(meetingType)
        self.lastSyncedAt = lastSyncedAt
        self.aiNotesFreshnessStateRawValue = aiNotesFreshnessState.rawValue
        self.lastAINotesTranscriptFingerprint = lastAINotesTranscriptFingerprint
        self.hasPendingImageTextRefreshValue = hasPendingImageTextRefresh
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.segments = segments
        self.chatMessages = chatMessages
        self.chatSessions = chatSessions
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

    var audioEnhancedNotes: String {
        get { audioEnhancedNotesValue ?? "" }
        set { audioEnhancedNotesValue = newValue }
    }

    var audioEnhancedNotesStatus: AudioEnhancedNotesStatus {
        get { AudioEnhancedNotesStatus(rawValue: audioEnhancedNotesStatusRawValueValue ?? "") ?? .idle }
        set { audioEnhancedNotesStatusRawValueValue = newValue.rawValue }
    }

    var postStopProcessingStage: MeetingPostStopProcessingStage {
        get { MeetingPostStopProcessingStage(rawValue: postStopProcessingStageRawValueValue ?? "") ?? .idle }
        set { postStopProcessingStageRawValueValue = newValue.rawValue }
    }

    var audioEnhancedNotesError: String {
        get { audioEnhancedNotesErrorValue ?? "" }
        set { audioEnhancedNotesErrorValue = newValue }
    }

    var meetingTypeRaw: String {
        get { Self.normalizedMeetingTypeRaw(meetingTypeRawValue) }
        set { meetingTypeRawValue = Self.normalizedMeetingTypeRaw(newValue) }
    }

    var meetingType: String {
        get { meetingTypeRaw }
        set { meetingTypeRaw = newValue }
    }

    var noteAttachmentFileNames: [String] {
        get { noteAttachmentFileNamesValue ?? [] }
        set { noteAttachmentFileNamesValue = newValue }
    }

    var noteAttachmentAssetIdentifiersByFileName: [String: String] {
        get {
            Self.decodeAttachmentAssetIdentifiers(
                noteAttachmentAssetIdentifiersRawValue ?? Self.encodeAttachmentAssetIdentifiers([:])
            )
        }
        set { noteAttachmentAssetIdentifiersRawValue = Self.encodeAttachmentAssetIdentifiers(newValue) }
    }

    var noteAttachmentRemoteIDsByFileName: [String: String] {
        get {
            Self.decodeAttachmentAssetIdentifiers(
                noteAttachmentRemoteIDsRawValue ?? Self.encodeAttachmentAssetIdentifiers([:])
            )
        }
        set { noteAttachmentRemoteIDsRawValue = Self.encodeAttachmentAssetIdentifiers(newValue) }
    }

    var noteAttachmentExtractedTextByFileName: [String: String] {
        get {
            Self.decodeAttachmentAssetIdentifiers(
                noteAttachmentExtractedTextsRawValue ?? Self.encodeAttachmentAssetIdentifiers([:])
            )
        }
        set { noteAttachmentExtractedTextsRawValue = Self.encodeAttachmentAssetIdentifiers(newValue) }
    }

    var noteAttachmentPendingDeleteIDs: [String] {
        get {
            Self.decodeStringArray(noteAttachmentPendingDeleteIDsRawValue ?? Self.encodeStringArray([]))
        }
        set { noteAttachmentPendingDeleteIDsRawValue = Self.encodeStringArray(newValue) }
    }

    var noteAttachmentTextContext: String {
        get { noteAttachmentTextContextValue ?? "" }
        set { noteAttachmentTextContextValue = newValue }
    }

    var noteAttachmentTextStatus: AnnotationImageTextStatus {
        get { AnnotationImageTextStatus(rawValue: noteAttachmentTextStatusRawValue ?? "") ?? .idle }
        set { noteAttachmentTextStatusRawValue = newValue.rawValue }
    }

    var audioCloudSyncEnabled: Bool {
        get { audioCloudSyncEnabledValue ?? true }
        set { audioCloudSyncEnabledValue = newValue }
    }

    var speakers: [String: String] {
        get { Self.decodeSpeakers(speakersRawValue ?? Self.encodeSpeakers([:])) }
        set { speakersRawValue = Self.encodeSpeakers(newValue) }
    }

    var speakerDiarizationState: SpeakerDiarizationState {
        get { SpeakerDiarizationState(rawValue: speakerDiarizationStateRawValue ?? "") ?? .idle }
        set { speakerDiarizationStateRawValue = newValue.rawValue }
    }

    var transcriptPipelineState: TranscriptPipelineState {
        get {
            if let rawValue = transcriptPipelineStateRawValue,
               let state = TranscriptPipelineState(rawValue: rawValue) {
                return state
            }

            return Self.legacyTranscriptPipelineState(
                status: status,
                speakerDiarizationState: speakerDiarizationState
            )
        }
        set { transcriptPipelineStateRawValue = newValue.rawValue }
    }

    var aiNotesFreshnessState: AINotesFreshnessState {
        get {
            var state = AINotesFreshnessState(rawValue: aiNotesFreshnessStateRawValue ?? "") ?? .fresh
            if hasPendingImageTextRefreshValue == true {
                state = state.settingAttachmentChanges(true)
            }
            return state
        }
        set {
            aiNotesFreshnessStateRawValue = newValue.rawValue
            hasPendingImageTextRefreshValue = newValue.includesAttachmentChanges
        }
    }

    var hasPendingImageTextRefresh: Bool {
        get { aiNotesFreshnessState.includesAttachmentChanges }
        set { aiNotesFreshnessState = aiNotesFreshnessState.settingAttachmentChanges(newValue) }
    }

    var hasNoteAttachments: Bool {
        !noteAttachmentFileNames.isEmpty
    }

    var hasNoteAttachmentText: Bool {
        !noteAttachmentTextContext.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var displayTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? AppStrings.current.untitledMeeting : trimmed
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

    var orderedChatSessions: [ChatSession] {
        chatSessions.sorted { lhs, rhs in
            if lhs.updatedAt == rhs.updatedAt {
                return lhs.createdAt > rhs.createdAt
            }
            return lhs.updatedAt > rhs.updatedAt
        }
    }

    var transcriptText: String {
        orderedSegments.map(\.text).joined(separator: "\n")
    }

    var transcriptFingerprint: String? {
        Self.transcriptFingerprint(from: transcriptText)
    }

    var hasTranscriptNotesRefreshHint: Bool {
        aiNotesFreshnessState.includesTranscriptChanges
    }

    var hasAttachmentNotesRefreshHint: Bool {
        aiNotesFreshnessState.includesAttachmentChanges
    }

    var searchIndexText: String {
        MeetingSearchIndexBuilder.searchIndexText(for: self)
    }

    func displayName(forSpeaker speaker: String) -> String {
        let normalized = speaker.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            return AppStrings.current.speakerLabel(1)
        }

        if let displayName = speakers[normalized]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !displayName.isEmpty {
            return displayName
        }

        if let index = Self.generatedSpeakerIndex(from: normalized) {
            return AppStrings.current.speakerLabel(index)
        }

        return normalized
    }

    func setDisplayName(_ displayName: String, forSpeaker speaker: String) {
        let normalizedSpeaker = speaker.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedSpeaker.isEmpty else { return }

        var updatedSpeakers = speakers
        let normalizedDisplayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)

        if normalizedDisplayName.isEmpty {
            updatedSpeakers.removeValue(forKey: normalizedSpeaker)
        } else {
            updatedSpeakers[normalizedSpeaker] = normalizedDisplayName
        }

        speakers = updatedSpeakers
    }

    func markPending() {
        updatedAt = .now
        if syncState != .syncing {
            syncState = .pending
        }
    }

    private static func encodeSpeakers(_ speakers: [String: String]) -> String {
        guard JSONSerialization.isValidJSONObject(speakers),
              let data = try? JSONSerialization.data(withJSONObject: speakers, options: [.sortedKeys]),
              let value = String(data: data, encoding: .utf8) else {
            return "{}"
        }

        return value
    }

    private static func normalizedMeetingTypeRaw(_ value: String?) -> String {
        guard let normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              let meetingType = MeetingTypeOption(rawValue: normalized) else {
            return MeetingTypeOption.general.rawValue
        }

        return meetingType.rawValue
    }

    private static func decodeSpeakers(_ rawValue: String) -> [String: String] {
        guard let data = rawValue.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let speakers = object as? [String: String] else {
            return [:]
        }

        return speakers
    }

    private static func encodeAttachmentAssetIdentifiers(_ mapping: [String: String]) -> String {
        guard JSONSerialization.isValidJSONObject(mapping),
              let data = try? JSONSerialization.data(withJSONObject: mapping, options: [.sortedKeys]),
              let value = String(data: data, encoding: .utf8) else {
            return "{}"
        }

        return value
    }

    private static func decodeAttachmentAssetIdentifiers(_ rawValue: String) -> [String: String] {
        guard let data = rawValue.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let mapping = object as? [String: String] else {
            return [:]
        }

        return mapping
    }

    private static func encodeStringArray(_ values: [String]) -> String {
        guard JSONSerialization.isValidJSONObject(values),
              let data = try? JSONSerialization.data(withJSONObject: values, options: [.sortedKeys]),
              let value = String(data: data, encoding: .utf8) else {
            return "[]"
        }

        return value
    }

    private static func decodeStringArray(_ rawValue: String) -> [String] {
        guard let data = rawValue.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let values = object as? [String] else {
            return []
        }

        return values
    }

    private static func generatedSpeakerIndex(from speaker: String) -> Int? {
        guard speaker.hasPrefix("spk_") else { return nil }
        guard let index = Int(speaker.dropFirst(4)), index > 0 else { return nil }
        return index
    }

    private static func legacyTranscriptPipelineState(
        status: MeetingStatus,
        speakerDiarizationState: SpeakerDiarizationState
    ) -> TranscriptPipelineState {
        switch status {
        case .transcribing:
            return speakerDiarizationState == .processing ? .refining : .initializing
        case .transcriptionFailed:
            return .failed
        case .ended:
            return .ready
        case .idle, .recording, .paused:
            return .idle
        }
    }

    private static func transcriptFingerprint(from transcript: String) -> String? {
        let normalizedTranscript = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedTranscript.isEmpty else { return nil }
        let digest = SHA256.hash(data: Data(normalizedTranscript.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
