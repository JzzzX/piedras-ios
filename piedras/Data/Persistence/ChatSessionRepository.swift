import Foundation
import SwiftData

@MainActor
final class ChatSessionRepository {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func fetchSessions(scope: ChatSessionScope, meetingID: String? = nil) throws -> [ChatSession] {
        let descriptor = FetchDescriptor<ChatSession>(
            sortBy: [SortDescriptor(\ChatSession.updatedAt, order: .reverse)]
        )
        return try modelContext.fetch(descriptor).filter { session in
            guard session.scope == scope else { return false }
            if scope == .meeting {
                return session.meeting?.id == meetingID
            }
            return session.meeting == nil
        }
    }

    @discardableResult
    func makeDraftSession(scope: ChatSessionScope, meeting: Meeting?) -> ChatSession {
        let session = ChatSession(scope: scope, meeting: meeting)
        modelContext.insert(session)
        if let meeting {
            meeting.chatSessions.append(session)
        }
        return session
    }

    @discardableResult
    func appendUserMessage(_ content: String, to session: ChatSession) -> ChatMessage {
        appendMessage(role: "user", content: content, to: session)
    }

    @discardableResult
    func appendAssistantPlaceholder(to session: ChatSession) -> ChatMessage {
        appendMessage(role: "assistant", content: "", to: session)
    }

    func save() throws {
        try modelContext.save()
    }

    func delete(_ session: ChatSession) throws {
        modelContext.delete(session)
        try save()
    }

    func deleteAllSessions() throws {
        let descriptor = FetchDescriptor<ChatSession>()
        let sessions = try modelContext.fetch(descriptor)
        for session in sessions {
            modelContext.delete(session)
        }
        try save()
    }

    func migrateLegacyMeetingChatsIfNeeded(for meeting: Meeting) throws {
        guard !meeting.chatMessages.isEmpty else { return }
        guard meeting.chatSessions.isEmpty else { return }

        let orderedMessages = meeting.orderedChatMessages
        let firstTimestamp = orderedMessages.first?.timestamp ?? meeting.updatedAt
        let lastTimestamp = orderedMessages.last?.timestamp ?? firstTimestamp
        let title = orderedMessages.first(where: { $0.role == "user" })?.content.trimmingCharacters(in: .whitespacesAndNewlines)
        let session = ChatSession(
            scope: .meeting,
            title: title ?? "",
            createdAt: firstTimestamp,
            updatedAt: lastTimestamp,
            meeting: meeting
        )
        modelContext.insert(session)
        meeting.chatSessions.append(session)

        for message in orderedMessages {
            message.session = session
            session.messages.append(message)
        }

        try save()
    }

    @discardableResult
    private func appendMessage(role: String, content: String, to session: ChatSession) -> ChatMessage {
        let message = ChatMessage(
            role: role,
            content: content,
            timestamp: .now,
            orderIndex: session.orderedMessages.count
        )
        message.meeting = session.meeting
        message.session = session
        session.messages.append(message)
        session.updatedAt = message.timestamp
        if session.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, role == "user" {
            session.title = content.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return message
    }
}
