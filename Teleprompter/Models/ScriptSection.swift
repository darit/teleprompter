import Foundation
import SwiftData

@Model
final class ScriptSection {
    var slideNumber: Int
    var label: String
    var content: String
    var order: Int
    var accentColorHex: String
    var isAIRefined: Bool

    init(
        slideNumber: Int,
        label: String,
        content: String,
        order: Int,
        accentColorHex: String,
        isAIRefined: Bool = false
    ) {
        self.slideNumber = slideNumber
        self.label = label
        self.content = content
        self.order = order
        self.accentColorHex = accentColorHex
        self.isAIRefined = isAIRefined
    }
}
