import Foundation
import SwiftData

@Model
final class PersistedChatMessage {
    var role: String
    var content: String
    var timestamp: Date
    var order: Int

    init(role: String, content: String, timestamp: Date = .now, order: Int) {
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.order = order
    }

    func toChatMessage() -> ChatMessage {
        ChatMessage(
            role: ChatMessage.Role(rawValue: role) ?? .user,
            content: content,
            timestamp: timestamp
        )
    }

    static func from(_ message: ChatMessage, order: Int) -> PersistedChatMessage {
        PersistedChatMessage(
            role: message.role.rawValue,
            content: message.content,
            timestamp: message.timestamp,
            order: order
        )
    }
}
