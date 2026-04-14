import Testing
import SwiftUI
import UIKit
@testable import CocoInterview

struct AppThemeTests {
    @Test
    func appTitleUsesBrandOnlyWordmark() {
        let chinese = AppStringTable(language: .chinese)
        let english = AppStringTable(language: .english)

        #expect(chinese.appTitle == "椰子面试")
        #expect(english.appTitle == "椰子面试")
    }

    @Test
    func deleteNoteActionAccessibilityLabelUsesSpecificCopy() {
        let chinese = AppStringTable(language: .chinese)
        let english = AppStringTable(language: .english)

        #expect(chinese.deleteNoteAction == "删除笔记")
        #expect(english.deleteNoteAction == "Delete note")
    }

    @Test
    func bodyUIFontUsesProportionalSystemFont() {
        let font = AppTheme.bodyUIFont(size: 16, weight: .semibold)

        #expect(!font.fontDescriptor.symbolicTraits.contains(.traitMonoSpace))
    }

    @Test
    func themeExposesSubtleContentChromeMetrics() {
        #expect(AppTheme.subtleBorderWidth == 1)
        #expect(AppTheme.compactIconSize == 32)
    }

    @Test
    func themeUsesHigherContrastPaperPaletteForHomeUI() {
        #expect(UIColor(AppTheme.background).hexRGB == 0xF3ECDD)
        #expect(UIColor(AppTheme.surface).hexRGB == 0xFAF5EB)
        #expect(UIColor(AppTheme.dockSurface).hexRGB == 0xE8E1D0)
        #expect(UIColor(AppTheme.border).hexRGB == 0xC9B8A3)
        #expect(UIColor(AppTheme.ink).hexRGB == 0x1E1A17)
        #expect(UIColor(AppTheme.mutedInk).hexRGB == 0x7D6E60)
        #expect(UIColor(AppTheme.highlight).hexRGB == 0xBC6C4D)
        #expect(AppTheme.retroBorderWidth == 1)
        #expect(AppTheme.retroShadowOffset == 3)
    }

    @Test
    func themeSeparatesMossInkBrandingFromRecordingHighlight() {
        #expect(UIColor(AppTheme.brandInk).hexRGB == 0x31493F)
        #expect(UIColor(AppTheme.brandInkMuted).hexRGB == 0x61786C)
        #expect(UIColor(AppTheme.brandInkSoft).hexRGB == 0xDFE7E1)
        #expect(UIColor(AppTheme.highlight).hexRGB == 0xBC6C4D)
        #expect(UIColor(AppTheme.highlightPressed).hexRGB == 0x9E5D43)
    }

    @Test
    func themeAddsMinimalNotesChromeForMossInkHomeRows() {
        #expect(UIColor(AppTheme.noteSectionRule).hexRGB == 0xCED7D2)
        #expect(UIColor(AppTheme.notePressFill).hexRGB == 0xEEF2EE)
        #expect(UIColor(AppTheme.noteIconWash).hexRGB == 0xF1ECE2)
    }

    @Test
    func themePromotesMossInkToGlobalPrimaryActionRole() {
        #expect(UIColor(AppTheme.primaryActionFill).hexRGB == 0x31493F)
        #expect(UIColor(AppTheme.primaryActionPressedFill).hexRGB == 0x24372F)
        #expect(UIColor(AppTheme.primaryActionForeground).hexRGB == 0xFAF5EB)
        #expect(UIColor(AppTheme.selectedChromeFill).hexRGB == 0xDFE7E1)
    }

    @Test
    func themeAddsDarkWineDestructiveChromeForHomeSwipeDelete() {
        #expect(UIColor(AppTheme.destructiveActionFill).hexRGB == 0x8E3E43)
        #expect(UIColor(AppTheme.destructiveActionPressedFill).hexRGB == 0x6F2E33)
        #expect(UIColor(AppTheme.destructiveActionBorder).hexRGB == 0x6F2E33)
        #expect(UIColor(AppTheme.destructiveActionShadow).hexRGB == 0xC9B8A3)
    }

    @Test
    func homeMetadataComponentsSeparateTimestampAndDuration() {
        let meeting = Meeting(
            title: "设计评审",
            date: Date(timeIntervalSince1970: 1_742_797_500), // 2025-03-24 15:05:00 UTC
            durationSeconds: 325
        )
        let calendar = Calendar(identifier: .gregorian)
        let referenceDate = meeting.date.addingTimeInterval(60)

        #expect(
            meeting.homeMetadataComponents(referenceDate: referenceDate, calendar: calendar)
                == [meeting.compactTimestampLabel, "05:25"]
        )
    }

    @Test
    func sessionCountBadgeFormatsCountsForCompactToolbarChrome() {
        #expect(SessionCountBadge.displayText(for: 0) == nil)
        #expect(SessionCountBadge.displayText(for: 1) == "1")
        #expect(SessionCountBadge.displayText(for: 9) == "9")
        #expect(SessionCountBadge.displayText(for: 10) == "9+")
        #expect(SessionCountBadge.displayText(for: 42) == "9+")
    }

    @Test
    func chatHistoryAccessibilityLabelCarriesLocalizedCountSummary() {
        let chinese = AppStringTable(language: .chinese)
        let english = AppStringTable(language: .english)

        #expect(
            SessionCountBadge.historyButtonAccessibilityLabel(
                baseLabel: chinese.chatHistoryTitle,
                count: 0,
                strings: chinese
            ) == "历史对话，0 条"
        )
        #expect(
            SessionCountBadge.historyButtonAccessibilityLabel(
                baseLabel: chinese.chatHistoryTitle,
                count: 2,
                strings: chinese
            ) == "历史对话，2 条"
        )
        #expect(
            SessionCountBadge.historyButtonAccessibilityLabel(
                baseLabel: chinese.chatHistoryTitle,
                count: 10,
                strings: chinese
            ) == "历史对话，9 条以上"
        )

        #expect(
            SessionCountBadge.historyButtonAccessibilityLabel(
                baseLabel: english.chatHistoryTitle,
                count: 0,
                strings: english
            ) == "Chat History, 0 chats"
        )
        #expect(
            SessionCountBadge.historyButtonAccessibilityLabel(
                baseLabel: english.chatHistoryTitle,
                count: 2,
                strings: english
            ) == "Chat History, 2 chats"
        )
        #expect(
            SessionCountBadge.historyButtonAccessibilityLabel(
                baseLabel: english.chatHistoryTitle,
                count: 10,
                strings: english
            ) == "Chat History, 9 or more chats"
        )
    }
}

private extension UIColor {
    var hexRGB: UInt32 {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0

        getRed(&red, green: &green, blue: &blue, alpha: &alpha)

        return (UInt32(round(red * 255)) << 16)
            | (UInt32(round(green * 255)) << 8)
            | UInt32(round(blue * 255))
    }
}
