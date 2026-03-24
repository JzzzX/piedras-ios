import CoreGraphics
import Testing
@testable import piedras

struct MeetingDetailChromeTests {
    @Test
    func nonRecordingTopBarKeepsTranscriptShareAndMoreOnly() {
        let actions = MeetingDetailChrome.topBarActions(isRecording: false)

        #expect(actions == [.transcript, .share, .more])
    }

    @Test
    func actionMenuChromeUsesInvisibleBackdropAndLocalShadowOnly() {
        let chrome = MeetingDetailChrome.actionMenuChrome

        #expect(chrome.backdropOpacity == 0.001)
        #expect(chrome.haloExpansion == CGFloat(7))
        #expect(chrome.haloOpacity == 0.3)
        #expect(chrome.shadowOffset == CGFloat(3))
        #expect(chrome.shadowOpacity == 0.34)
    }

    @Test
    func actionMenuPlacesRegenerateNotesAfterEdit() {
        let items = MeetingDetailChrome.actionMenuItems(
            isRecording: false,
            hasTranscript: true,
            canRetryTranscription: false
        )

        #expect(items.map(\.accessibilityIdentifier) == [
            "MeetingDetailActionEditAINotes",
            "MeetingDetailActionRegenerateNotes",
            "MeetingDetailActionCopyNotes",
            "MeetingDetailActionCopyTranscript",
        ])
        #expect(items[1].title == AppStrings.current.regenerateNotes)
        #expect(items[1].systemName == "arrow.clockwise")
    }

    @Test
    func notesCTAUsesSimpleNoteGlyphAndCenteredLayout() {
        let config = MeetingDetailChrome.entry(for: .notes)

        #expect(config.title == AppStrings.current.myNotes)
        #expect(config.glyph == "square.and.pencil")
        #expect(config.centersContent)
    }

    @Test
    func chatCTAUsesTerminalPromptGlyphAndCenteredLayout() {
        let config = MeetingDetailChrome.entry(for: .chat)

        #expect(config.title == AppStrings.current.chatWithNote)
        #expect(config.glyph == ">_")
        #expect(config.centersContent)
    }

    @Test
    func sheetHeadersKeepNotesMinimalAndShowChatScopeHint() {
        let notes = MeetingDetailChrome.sheet(for: .notes)
        let chat = MeetingDetailChrome.sheet(for: .chat)

        #expect(notes.title == AppStrings.current.myNotes)
        #expect(notes.glyph == "square.and.pencil")
        #expect(notes.hint == nil)

        #expect(chat.title == AppStrings.current.chatWithNote)
        #expect(chat.glyph == ">_")
        #expect(chat.hint == AppStrings.current.meetingChatScopeHint)
    }
}
