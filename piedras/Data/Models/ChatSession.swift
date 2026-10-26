import Foundation
import SwiftData

enum ChatSessionScope: String, Codable {
    case global
    case meeting
}

@Model
final class ChatSession {
    @Attribute(.unique) var id: String
    var scopeRaw: String
    var title: String
    var createdAt: Date
    var updatedAt: Date
    var meeting: Meeting?

    @Relationship(deleteRule: .cascade, inverse: \ChatMessage.session)
    var messages: [ChatMessage]

    init(
        id: String = UUID().uuidString.lowercased(),
        scope: ChatSessionScope,
        title: String = "",
        createdAt: Date = .now,
        updatedAt: Date = .now,
        meeting: Meeting? = nil,
        messages: [ChatMessage] = []
    ) {
        self.id = id
        self.scopeRaw = scope.rawValue
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.meeting = meeting
        self.messages = messages
    }

    var scope: ChatSessionScope {
        get { ChatSessionScope(rawValue: scopeRaw) ?? .meeting }
        set { scopeRaw = newValue.rawValue }
    }

    var orderedMessages: [ChatMessage] {
        messages.sorted { lhs, rhs in
            if lhs.orderIndex == rhs.orderIndex {
                return lhs.timestamp < rhs.timestamp
            }
            return lhs.orderIndex < rhs.orderIndex
        }
    }
}
