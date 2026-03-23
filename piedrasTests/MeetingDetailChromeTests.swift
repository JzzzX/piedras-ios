import Testing
@testable import piedras

struct MeetingDetailChromeTests {
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
    func sheetHeadersAreMinimalAndCarryNoHintText() {
        let notes = MeetingDetailChrome.sheet(for: .notes)
        let chat = MeetingDetailChrome.sheet(for: .chat)

        #expect(notes.title == AppStrings.current.myNotes)
        #expect(notes.glyph == "square.and.pencil")
        #expect(notes.hint == nil)

        #expect(chat.title == AppStrings.current.chatWithNote)
        #expect(chat.glyph == ">_")
        #expect(chat.hint == nil)
    }
}
