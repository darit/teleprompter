import Foundation
import SwiftData

@Model
final class Script {
    var name: String
    @Relationship(deleteRule: .cascade) var sections: [ScriptSection]
    var createdAt: Date
    var modifiedAt: Date
    var scrollSpeed: Double
    var fontSize: Double
    var targetDuration: Double?

    var sortedSections: [ScriptSection] {
        sections.sorted { $0.order < $1.order }
    }

    init(
        name: String,
        sections: [ScriptSection] = [],
        scrollSpeed: Double = 1.0,
        fontSize: Double = 16.0,
        targetDuration: Double? = nil
    ) {
        self.name = name
        self.sections = sections
        self.createdAt = Date.now
        self.modifiedAt = Date.now
        self.scrollSpeed = scrollSpeed
        self.fontSize = fontSize
        self.targetDuration = targetDuration
    }
}
