import Testing
import SwiftUI
import UIKit
@testable import piedras

struct AppThemeTests {
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
    func themeUsesWarmerLighterRetroChromeTokens() {
        #expect(UIColor(AppTheme.border).hexRGB == 0xC8B9A6)
        #expect(UIColor(AppTheme.mutedInk).hexRGB == 0x8A7E6B)
        #expect(UIColor(AppTheme.subtleInk).hexRGB == 0xB5A998)
        #expect(UIColor(AppTheme.caramel).hexRGB == 0x9C7B5C)
        #expect(UIColor(AppTheme.iconBackground).hexRGB == 0xE8DED0)
        #expect(AppTheme.retroBorderWidth == 1)
        #expect(AppTheme.retroShadowOffset == 3)
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
