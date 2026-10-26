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
    func recordingTopBarShowsAttachmentsAndMoreOnly() {
        let actions = MeetingDetailChrome.topBarActions(isRecording: true)

        #expect(actions == [.attachments, .more])
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
            canRetryTranscription: false,
            showsNotesRefreshHint: false
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
    func recordingActionMenuOnlyKeepsCopyNotes() {
        let items = MeetingDetailChrome.actionMenuItems(
            isRecording: true,
            hasTranscript: true,
            canRetryTranscription: true,
            showsNotesRefreshHint: false
        )

        #expect(items.map(\.accessibilityIdentifier) == [
            "MeetingDetailActionCopyNotes",
        ])
        #expect(items.first?.title == AppStrings.current.copyNotes)
    }

    @Test
    func actionMenuUsesRefreshTitleWhenNotesAreStale() {
        let items = MeetingDetailChrome.actionMenuItems(
            isRecording: false,
            hasTranscript: true,
            canRetryTranscription: false,
            showsNotesRefreshHint: true
        )

        #expect(items[1].title == AppStrings.current.refreshNotes)
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

    @Test
    func recordingDocumentChromeRemovesAtmosphereLineAndSecondaryRecBadge() {
        let chrome = MeetingDetailChrome.recordingDocument

        #expect(chrome.showsAtmosphereLine == false)
        #expect(chrome.showsSecondaryRecBadge == false)
        #expect(chrome.titleEditSystemName == "pencil")
        #expect(chrome.notePromptSystemName == "square.and.pencil")
        #expect(chrome.notePromptTitle == AppStrings.current.recordingNotePromptTitle)
        #expect(chrome.notePromptHint == AppStrings.current.recordingNotePromptHint)
        #expect(chrome.notePromptMinHeight == CGFloat(136))
    }

    @Test
    func recordingDocumentPromptShowsOnlyWhenNotesAreEmptyAndEditorIsIdle() {
        #expect(MeetingDetailChrome.showsRecordingNotePrompt(notes: "", isEditorFocused: false))
        #expect(MeetingDetailChrome.showsRecordingNotePrompt(notes: " \n ", isEditorFocused: false))
        #expect(MeetingDetailChrome.showsRecordingNotePrompt(notes: "", isEditorFocused: true) == false)
        #expect(MeetingDetailChrome.showsRecordingNotePrompt(notes: "已有内容", isEditorFocused: false) == false)
    }

    @Test
    func recordingDocumentHidesEditorPlaceholderWhilePromptCardIsVisible() {
        #expect(
            MeetingDetailChrome.recordingNoteEditorPlaceholder(
                notes: "",
                isEditorFocused: false
            ) == ""
        )
        #expect(
            MeetingDetailChrome.recordingNoteEditorPlaceholder(
                notes: "",
                isEditorFocused: true
            ) == AppStrings.current.writeHere
        )
        #expect(
            MeetingDetailChrome.recordingNoteEditorPlaceholder(
                notes: "已有内容",
                isEditorFocused: false
            ) == AppStrings.current.writeHere
        )
    }

    @Test
    func recordingAttachmentDockMetricsShowAtMostTwoRows() {
        let hidden = RecordingAttachmentDockMetrics.forAttachmentCount(0)
        let singleRow = RecordingAttachmentDockMetrics.forAttachmentCount(4)
        let doubleRow = RecordingAttachmentDockMetrics.forAttachmentCount(8)
        let overflow = RecordingAttachmentDockMetrics.forAttachmentCount(10)

        #expect(hidden.isVisible == false)
        #expect(hidden.visibleRowCount == 0)
        #expect(hidden.showsInternalScroll == false)

        #expect(singleRow.isVisible)
        #expect(singleRow.visibleRowCount == 1)
        #expect(singleRow.showsInternalScroll == false)

        #expect(doubleRow.isVisible)
        #expect(doubleRow.visibleRowCount == 2)
        #expect(doubleRow.showsInternalScroll == false)

        #expect(overflow.isVisible)
        #expect(overflow.visibleRowCount == 2)
        #expect(overflow.showsInternalScroll)
    }

    @Test
    func recordingAttachmentPreviewModeCompressesWhileEditing() {
        let hidden = RecordingAttachmentPreviewMode.forAttachmentCount(0, isEditorFocused: true)
        let defaultMode = RecordingAttachmentPreviewMode.forAttachmentCount(3, isEditorFocused: false)
        let compactMode = RecordingAttachmentPreviewMode.forAttachmentCount(3, isEditorFocused: true)

        #expect(hidden == .hidden)
        #expect(defaultMode == .grid(RecordingAttachmentDockMetrics.forAttachmentCount(3)))
        #expect(compactMode == .compactStrip)
    }

    @Test
    func meetingTypeLabelUsesNoteCopy() {
        let chinese = AppStringTable(language: .chinese)
        let english = AppStringTable(language: .english)

        #expect(chinese.meetingTypeLabel == "笔记类型")
        #expect(english.meetingTypeLabel == "Note type")
    }
}
