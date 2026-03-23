import Testing
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
