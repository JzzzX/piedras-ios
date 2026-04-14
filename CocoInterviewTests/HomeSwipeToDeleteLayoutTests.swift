import Foundation
import Testing
import CoreGraphics
@testable import CocoInterview

struct HomeSwipeToDeleteLayoutTests {
    @Test
    func deleteActionRetreatsAsRowCloses() {
        let fullyOpenOffset = HomeSwipeToDeleteMetrics.actionOffset(
            forContentOffset: -HomeSwipeToDeleteMetrics.totalActionWidth(actionCount: 1),
            actionCount: 1
        )
        let partiallyClosedOffset = HomeSwipeToDeleteMetrics.actionOffset(
            forContentOffset: -HomeSwipeToDeleteMetrics.totalActionWidth(actionCount: 1) / 2,
            actionCount: 1
        )
        let fullyClosedOffset = HomeSwipeToDeleteMetrics.actionOffset(forContentOffset: 0, actionCount: 1)

        #expect(fullyOpenOffset == 0)
        #expect(partiallyClosedOffset > fullyOpenOffset)
        #expect(fullyClosedOffset > partiallyClosedOffset)
    }

    @Test
    func multiActionDeleteOffsetUsesCombinedActionWidth() {
        let fullyOpenOffset = HomeSwipeToDeleteMetrics.actionOffset(
            forContentOffset: -HomeSwipeToDeleteMetrics.totalActionWidth(actionCount: 2),
            actionCount: 2
        )
        let partiallyClosedOffset = HomeSwipeToDeleteMetrics.actionOffset(
            forContentOffset: -HomeSwipeToDeleteMetrics.totalActionWidth(actionCount: 2) / 2,
            actionCount: 2
        )
        let fullyClosedOffset = HomeSwipeToDeleteMetrics.actionOffset(forContentOffset: 0, actionCount: 2)

        #expect(fullyOpenOffset == 0)
        #expect(partiallyClosedOffset > fullyOpenOffset)
        #expect(fullyClosedOffset > partiallyClosedOffset)
    }

    @Test
    func deleteActionOnlyBecomesHittableAfterEnoughReveal() {
        #expect(HomeSwipeToDeleteMetrics.isActionHittable(forContentOffset: -12, actionCount: 1) == false)
        #expect(HomeSwipeToDeleteMetrics.isActionHittable(forContentOffset: -56, actionCount: 1) == true)
    }

    @Test
    func multiActionButtonsBecomeHittableWithoutRevealingEntireStrip() {
        #expect(HomeSwipeToDeleteMetrics.isActionHittable(forContentOffset: -40, actionCount: 2) == false)
        #expect(HomeSwipeToDeleteMetrics.isActionHittable(forContentOffset: -56, actionCount: 2) == true)
    }

    @Test
    func horizontalPanPreferenceRejectsMostlyVerticalGestures() {
        #expect(HomeSwipeToDeleteMetrics.prefersHorizontalPan(velocity: CGPoint(x: -180, y: 40)) == true)
        #expect(HomeSwipeToDeleteMetrics.prefersHorizontalPan(velocity: CGPoint(x: -40, y: 180)) == false)
    }
}
