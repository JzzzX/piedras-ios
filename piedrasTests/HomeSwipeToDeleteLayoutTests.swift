import Foundation
import Testing
@testable import piedras

struct HomeSwipeToDeleteLayoutTests {
    @Test
    func deleteActionRetreatsAsRowCloses() {
        let fullyOpenOffset = HomeSwipeToDeleteMetrics.actionOffset(forContentOffset: -HomeSwipeToDeleteMetrics.actionWidth)
        let partiallyClosedOffset = HomeSwipeToDeleteMetrics.actionOffset(forContentOffset: -HomeSwipeToDeleteMetrics.actionWidth / 2)
        let fullyClosedOffset = HomeSwipeToDeleteMetrics.actionOffset(forContentOffset: 0)

        #expect(fullyOpenOffset == 0)
        #expect(partiallyClosedOffset > fullyOpenOffset)
        #expect(fullyClosedOffset > partiallyClosedOffset)
    }

    @Test
    func deleteActionOnlyBecomesHittableAfterEnoughReveal() {
        #expect(HomeSwipeToDeleteMetrics.isActionHittable(forContentOffset: -12) == false)
        #expect(HomeSwipeToDeleteMetrics.isActionHittable(forContentOffset: -56) == true)
    }
}
