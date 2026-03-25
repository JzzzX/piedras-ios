import Foundation

enum MeetingDetailChromeKind {
    case notes
    case chat
}

enum MeetingDetailToolbarAction: Equatable {
    case transcript
    case share
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

enum MeetingDetailChrome {
    static let actionMenuChrome = MeetingDetailActionMenuChrome(
        backdropOpacity: 0.001,
        haloExpansion: 7,
        haloOpacity: 0.3,
        shadowOffset: 3,
        shadowOpacity: 0.34
    )

    static func topBarActions(isRecording: Bool) -> [MeetingDetailToolbarAction] {
        if isRecording {
            return [.more]
        }

        return [.transcript, .share, .more]
    }

    static func actionMenuItems(
        isRecording: Bool,
        hasTranscript: Bool,
        canRetryTranscription: Bool
    ) -> [MeetingDetailMenuItemChrome] {
        var items = [
            MeetingDetailMenuItemChrome(
                title: AppStrings.current.editAINotes,
                systemName: "square.and.pencil",
                accessibilityIdentifier: "MeetingDetailActionEditAINotes"
            )
        ]

        if !isRecording {
            items.append(
                MeetingDetailMenuItemChrome(
                    title: AppStrings.current.regenerateNotes,
                    systemName: "arrow.clockwise",
                    accessibilityIdentifier: "MeetingDetailActionRegenerateNotes"
                )
            )
        }

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
}
