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
}
