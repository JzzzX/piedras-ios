import Foundation
import SwiftData
import Testing
@testable import piedras

@Suite(.serialized)
struct ChatSessionRepositoryTests {
    @MainActor
    @Test
    func persistsGlobalChatSessionsAndMessages() throws {
        let container = try ModelContainerFactory.makeContainer(inMemory: true)
        let repository = ChatSessionRepository(modelContext: container.mainContext)

        let session = repository.makeDraftSession(scope: .global, meeting: nil)
        repository.appendUserMessage("总结一下最近三次会议", to: session)
        repository.appendAssistantPlaceholder(to: session)
        try repository.save()

        let sessions = try repository.fetchSessions(scope: .global)

        #expect(sessions.count == 1)
        #expect(sessions.first?.scope == .global)
        #expect(sessions.first?.title == "总结一下最近三次会议")
        #expect(sessions.first?.orderedMessages.map(\.role) == ["user", "assistant"])
    }

    @MainActor
    @Test
    func migratesLegacyMeetingChatMessagesIntoSingleImportedSession() throws {
        let container = try ModelContainerFactory.makeContainer(inMemory: true)
        let context = container.mainContext
        let meeting = Meeting(
            id: "meeting-1",
            title: "测试会议",
            chatMessages: [
                ChatMessage(
                    id: "message-1",
                    role: "user",
                    content: "帮我总结重点",
                    timestamp: Date(timeIntervalSince1970: 100),
                    orderIndex: 0
                ),
                ChatMessage(
                    id: "message-2",
                    role: "assistant",
                    content: "重点是稳定性和删除交互。",
                    timestamp: Date(timeIntervalSince1970: 120),
                    orderIndex: 1
                ),
            ]
        )
        context.insert(meeting)
        try context.save()

        let repository = ChatSessionRepository(modelContext: context)
        try repository.migrateLegacyMeetingChatsIfNeeded(for: meeting)

        let sessions = try repository.fetchSessions(scope: .meeting, meetingID: meeting.id)

        #expect(sessions.count == 1)
        #expect(sessions.first?.meeting?.id == meeting.id)
        #expect(sessions.first?.title == "帮我总结重点")
        #expect(sessions.first?.orderedMessages.map(\.id) == ["message-1", "message-2"])
        #expect(meeting.chatSessions.count == 1)
    }
}
