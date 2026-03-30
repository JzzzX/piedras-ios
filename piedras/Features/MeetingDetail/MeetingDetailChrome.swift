import Foundation

struct MeetingDetailPresentationState: Equatable {
    let usesRecordingWorkspace: Bool
    let transcriptionStatus: FileTranscriptionStatusSnapshot?
    let showsEnhancedNotesProcessing: Bool

    init(
        meetingID: String,
        recordingSessionMeetingID: String?,
        recordingPhase: RecordingPhase,
        transcriptionStatus: FileTranscriptionStatusSnapshot?,
        isEnhancing: Bool,
        hasEnhancedNotes: Bool
    ) {
        let isCurrentRecordingMeeting = recordingSessionMeetingID == meetingID
        let isStoppingCurrentMeeting = isCurrentRecordingMeeting && recordingPhase == .stopping

        usesRecordingWorkspace = isCurrentRecordingMeeting
            && recordingPhase != .idle
            && recordingPhase != .stopping

        if let transcriptionStatus {
            self.transcriptionStatus = transcriptionStatus
        } else if isStoppingCurrentMeeting {
            self.transcriptionStatus = FileTranscriptionStatusSnapshot(
                phase: .finalizing,
                errorMessage: nil
            )
        } else {
            self.transcriptionStatus = nil
        }

        showsEnhancedNotesProcessing = isEnhancing || (isStoppingCurrentMeeting && !hasEnhancedNotes)
    }
}

enum MeetingDetailChromeKind {
    case notes
    case chat
}

enum MeetingDetailToolbarAction: Equatable {
    case transcript
    case share
    case attachments
    case more
}

struct MeetingDetailMenuItemChrome: Equatable {
    let title: String
    let systemName: String
    let accessibilityIdentifier: String
}

struct MeetingDetailActionMenuChrome: Equatable {
    let backdropOpacity: Double
    let haloExpansion: CGFloat
    let haloOpacity: Double
    let shadowOffset: CGFloat
    let shadowOpacity: Double
}

struct MeetingDetailEntryChrome {
    let title: String
    let glyph: String
    let usesSymbolImage: Bool
    let centersContent: Bool
}

struct MeetingDetailSheetChrome {
    let title: String
    let glyph: String
    let usesSymbolImage: Bool
    let hint: String?
}

struct MeetingDetailRecordingDocumentChrome: Equatable {
    let showsAtmosphereLine: Bool
    let showsSecondaryRecBadge: Bool
    let titleEditSystemName: String
    let notePromptSystemName: String
    let notePromptTitle: String
    let notePromptHint: String
    let notePromptMinHeight: CGFloat
}

enum MeetingDetailChrome {
    static let actionMenuChrome = MeetingDetailActionMenuChrome(
        backdropOpacity: 0.001,
        haloExpansion: 7,
        haloOpacity: 0.3,
        shadowOffset: 3,
        shadowOpacity: 0.34
    )

    static let recordingDocument = MeetingDetailRecordingDocumentChrome(
        showsAtmosphereLine: false,
        showsSecondaryRecBadge: false,
        titleEditSystemName: "pencil",
        notePromptSystemName: "square.and.pencil",
        notePromptTitle: AppStrings.current.recordingNotePromptTitle,
        notePromptHint: AppStrings.current.recordingNotePromptHint,
        notePromptMinHeight: 136
    )

    static func topBarActions(isRecording: Bool) -> [MeetingDetailToolbarAction] {
        if isRecording {
            return [.attachments, .more]
        }

        return [.transcript, .share, .more]
    }

    static func actionMenuItems(
        isRecording: Bool,
        hasTranscript: Bool,
        canRetryTranscription: Bool,
        showsNotesRefreshHint: Bool
    ) -> [MeetingDetailMenuItemChrome] {
        if isRecording {
            return [
                MeetingDetailMenuItemChrome(
                    title: AppStrings.current.copyNotes,
                    systemName: "doc.on.doc",
                    accessibilityIdentifier: "MeetingDetailActionCopyNotes"
                ),
            ]
        }

        var items = [
            MeetingDetailMenuItemChrome(
                title: AppStrings.current.editAINotes,
                systemName: "square.and.pencil",
                accessibilityIdentifier: "MeetingDetailActionEditAINotes"
            )
        ]
        items.append(
            MeetingDetailMenuItemChrome(
                title: showsNotesRefreshHint ? AppStrings.current.refreshNotes : AppStrings.current.regenerateNotes,
                systemName: "arrow.clockwise",
                accessibilityIdentifier: "MeetingDetailActionRegenerateNotes"
            )
        )

        items.append(
            contentsOf: [
                MeetingDetailMenuItemChrome(
                    title: AppStrings.current.copyNotes,
                    systemName: "doc.on.doc",
                    accessibilityIdentifier: "MeetingDetailActionCopyNotes"
                )
            ]
        )

        if hasTranscript {
            items.append(
                MeetingDetailMenuItemChrome(
                    title: AppStrings.current.copyTranscript,
                    systemName: "doc.on.doc",
                    accessibilityIdentifier: "MeetingDetailActionCopyTranscript"
                )
            )
        }

        if canRetryTranscription {
            items.append(
                MeetingDetailMenuItemChrome(
                    title: AppStrings.current.retryTranscription,
                    systemName: "arrow.clockwise",
                    accessibilityIdentifier: "MeetingDetailActionRetryTranscription"
                )
            )
        }

        return items
    }

    static func entry(for kind: MeetingDetailChromeKind) -> MeetingDetailEntryChrome {
        switch kind {
        case .notes:
            MeetingDetailEntryChrome(
                title: AppStrings.current.myNotes,
                glyph: "square.and.pencil",
                usesSymbolImage: true,
                centersContent: true
            )
        case .chat:
            MeetingDetailEntryChrome(
                title: AppStrings.current.chatWithNote,
                glyph: ">_",
                usesSymbolImage: false,
                centersContent: true
            )
        }
    }

    static func sheet(for kind: MeetingDetailChromeKind) -> MeetingDetailSheetChrome {
        switch kind {
        case .notes:
            MeetingDetailSheetChrome(
                title: AppStrings.current.myNotes,
                glyph: "square.and.pencil",
                usesSymbolImage: true,
                hint: nil
            )
        case .chat:
            MeetingDetailSheetChrome(
                title: AppStrings.current.chatWithNote,
                glyph: ">_",
                usesSymbolImage: false,
                hint: AppStrings.current.meetingChatScopeHint
            )
        }
    }

    static func showsRecordingNotePrompt(notes: String, isEditorFocused: Bool) -> Bool {
        notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isEditorFocused
    }

    static func recordingNoteEditorPlaceholder(notes: String, isEditorFocused: Bool) -> String {
        showsRecordingNotePrompt(notes: notes, isEditorFocused: isEditorFocused)
            ? ""
            : AppStrings.current.writeHere
    }

    static func recordingMetaLine(for meetingDate: Date) -> String {
        let date = meetingDate.formatted(.dateTime.month(.wide).day().year())
        let time = meetingDate.formatted(.dateTime.hour().minute())
        return "\(date) · \(time)"
    }
}
