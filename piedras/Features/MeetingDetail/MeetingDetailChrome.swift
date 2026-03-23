import Foundation

enum MeetingDetailChromeKind {
    case notes
    case chat
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
                hint: nil
            )
        }
    }
}
