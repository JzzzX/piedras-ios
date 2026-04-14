import CoreGraphics
import Testing
@testable import CocoInterview

struct EditorialDocumentEditorScrollTests {
    @Test
    func keepsCaretStableWhenStillInsideVisibleViewport() {
        let targetOffset = EditorialPinnedCaretMetrics.targetContentOffsetY(
            currentOffsetY: 0,
            viewportHeight: 240,
            contentHeight: 640,
            insetTop: 0,
            insetBottom: 0,
            caretRect: CGRect(x: 0, y: 72, width: 2, height: 22),
            topPadding: 32
        )

        #expect(targetOffset == nil)
    }

    @Test
    func pinsCaretNearTopWhenTypingLineFallsBelowViewport() {
        let targetOffset = EditorialPinnedCaretMetrics.targetContentOffsetY(
            currentOffsetY: 0,
            viewportHeight: 180,
            contentHeight: 640,
            insetTop: 0,
            insetBottom: 0,
            caretRect: CGRect(x: 0, y: 196, width: 2, height: 22),
            topPadding: 32
        )

        #expect(targetOffset == 164)
    }

    @Test
    func movesBackUpWhenCaretJumpsAboveVisibleViewport() {
        let targetOffset = EditorialPinnedCaretMetrics.targetContentOffsetY(
            currentOffsetY: 220,
            viewportHeight: 180,
            contentHeight: 640,
            insetTop: 0,
            insetBottom: 0,
            caretRect: CGRect(x: 0, y: 120, width: 2, height: 22),
            topPadding: 32
        )

        #expect(targetOffset == 88)
    }

    @Test
    func clampsPinnedOffsetToBottomBoundary() {
        let targetOffset = EditorialPinnedCaretMetrics.targetContentOffsetY(
            currentOffsetY: 220,
            viewportHeight: 180,
            contentHeight: 420,
            insetTop: 0,
            insetBottom: 0,
            caretRect: CGRect(x: 0, y: 390, width: 2, height: 22),
            topPadding: 32
        )

        #expect(targetOffset == 240)
    }
}
