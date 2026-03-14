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

    /// Original slide body text extracted from the PPTX file.
    var originalBodyText: String = ""
    /// Original speaker notes extracted from the PPTX file.
    var originalNotes: String = ""
    /// Relative path to the slide preview image (content card or LibreOffice render).
    var thumbnailRelativePath: String?

    init(
        slideNumber: Int,
        label: String,
        content: String,
        order: Int,
        accentColorHex: String,
        isAIRefined: Bool = false,
        originalBodyText: String = "",
        originalNotes: String = ""
    ) {
        self.slideNumber = slideNumber
        self.label = label
        self.content = content
        self.order = order
        self.accentColorHex = accentColorHex
        self.isAIRefined = isAIRefined
        self.originalBodyText = originalBodyText
        self.originalNotes = originalNotes
    }

    /// Value-type snapshot for UI display (breaks SwiftData observation chain).
    func toSnapshot() -> SectionSnapshot {
        SectionSnapshot(
            slideNumber: slideNumber,
            label: label,
            content: content,
            accentColorHex: accentColorHex,
            thumbnailRelativePath: thumbnailRelativePath ?? ""
        )
    }

    /// Reconstruct a SlideContent from the persisted original PPTX data.
    func toSlideContent() -> SlideContent {
        SlideContent(
            slideNumber: slideNumber,
            title: label,
            bodyText: originalBodyText,
            notes: originalNotes,
            images: []
        )
    }
}
