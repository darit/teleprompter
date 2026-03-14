import Foundation
import SwiftData

@Model
final class Script {
    var name: String
    @Relationship(deleteRule: .cascade) var sections: [ScriptSection]
    @Relationship(deleteRule: .cascade) var chatHistory: [PersistedChatMessage]
    var createdAt: Date
    var modifiedAt: Date
    var scrollSpeed: Double
    var fontSize: Double
    var targetDuration: Double?
    /// Stable identifier for file-based storage (slide images, etc.)
    var storageId: String = UUID().uuidString

    var sortedSections: [ScriptSection] {
        sections.sorted { $0.order < $1.order }
    }

    init(
        name: String,
        sections: [ScriptSection] = [],
        chatHistory: [PersistedChatMessage] = [],
        scrollSpeed: Double = 160.0,
        fontSize: Double = 16.0,
        targetDuration: Double? = nil
    ) {
        self.name = name
        self.sections = sections
        self.chatHistory = chatHistory
        self.createdAt = Date.now
        self.modifiedAt = Date.now
        self.scrollSpeed = scrollSpeed
        self.fontSize = fontSize
        self.targetDuration = targetDuration
    }
}
