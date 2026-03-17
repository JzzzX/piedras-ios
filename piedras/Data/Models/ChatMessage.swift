import Foundation
import SwiftData

@Model
final class ChatMessage {
    @Attribute(.unique) var id: String
    var role: String
    var content: String
    var timestamp: Date
    var orderIndex: Int
    var meeting: Meeting?

    init(
        id: String = UUID().uuidString.lowercased(),
        role: String,
        content: String,
        timestamp: Date = .now,
        orderIndex: Int
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.orderIndex = orderIndex
    }
}
