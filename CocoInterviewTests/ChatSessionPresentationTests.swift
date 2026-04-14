import Foundation
import Testing
@testable import CocoInterview

struct ChatSessionPresentationTests {
    @Test
    func groupsSessionsBySameRecencyRulesAsMeetingHome() {
        let now = Date(timeIntervalSince1970: 1_742_947_200)
        let calendar = Calendar(identifier: .gregorian)

        let sessions = [
            ChatSession(scope: .global, title: "today", updatedAt: now),
            ChatSession(scope: .global, title: "yesterday", updatedAt: calendar.date(byAdding: .day, value: -1, to: now)!),
            ChatSession(scope: .global, title: "week", updatedAt: calendar.date(byAdding: .day, value: -2, to: now)!),
            ChatSession(scope: .global, title: "earlier", updatedAt: calendar.date(byAdding: .day, value: -10, to: now)!),
        ]

        let sections = ChatSessionHistorySection.makeSections(from: sessions, now: now, calendar: calendar)

        #expect(sections.map { $0.bucket } == [.today, .yesterday, .earlierThisWeek, .earlier])
        #expect(sections.flatMap { $0.sessions }.map { $0.title } == ["today", "yesterday", "week", "earlier"])
    }

    @Test
    func metadataLineKeepsTimeSecondaryAndCompact() {
        let now = Date()
        let todaySession = ChatSession(scope: .global, title: "today", updatedAt: now)
        let earlierSession = ChatSession(
            scope: .global,
            title: "earlier",
            updatedAt: Calendar.current.date(byAdding: .day, value: -9, to: now)!
        )

        let todayMetadata = todaySession.historyMetadataLine(referenceDate: now)
        let earlierMetadata = earlierSession.historyMetadataLine(referenceDate: now)

        #expect(!todayMetadata.isEmpty)
        #expect(todayMetadata.contains(":"))
        #expect(!earlierMetadata.isEmpty)
        #expect(!earlierMetadata.contains(":"))
    }

}
