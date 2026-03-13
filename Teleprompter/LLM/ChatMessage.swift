import Foundation

struct ChatMessage: Identifiable, Sendable {
    let id = UUID()
    let role: Role
    let content: String
    let timestamp: Date
    /// Optional image attachments (PNG/JPEG data) for vision-capable models
    let images: [Data]

    enum Role: String, Sendable {
        case system
        case user
        case assistant
    }

    init(role: Role, content: String, timestamp: Date = .now, images: [Data] = []) {
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.images = images
    }
}
