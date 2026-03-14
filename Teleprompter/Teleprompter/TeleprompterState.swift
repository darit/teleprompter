import Foundation
import Observation

struct TeleprompterSection: Identifiable {
    let id = UUID()
    let slideNumber: Int
    let label: String
    let content: String
    let accentColorHex: String
    var thumbnailRelativePath: String = ""
}

@Observable
final class TeleprompterState {
    let sections: [TeleprompterSection]
    /// Display font size in points
    var fontSize: Double {
        didSet { sourceScript?.fontSize = fontSize }
    }
    /// Speaking pace in words per minute
    var scrollSpeed: Double {
        didSet { sourceScript?.scrollSpeed = scrollSpeed }
    }
    var scrollOffset: CGFloat = 0
    var isPlaying = false
    var currentSectionIndex = 0
    var opacity: Double = 1.0
    /// Background opacity (0 = fully transparent, 1 = solid black)
    var backgroundOpacity: Double = 0.85
    var isClickThrough = false
    /// Weak reference to persist WPM changes back to the source Script
    weak var sourceScript: Script?

    private static let minSpeed: Double = 60
    private static let maxSpeed: Double = 250
    private static let speedStep: Double = 10
    private static let minOpacity: Double = 0.2
    private static let maxOpacity: Double = 1.0
    private static let opacityStep: Double = 0.1
    private static let minFontSize: Double = 10
    private static let maxFontSize: Double = 48
    private static let fontSizeStep: Double = 2

    init(sections: [TeleprompterSection], fontSize: Double, scrollSpeed: Double) {
        self.sections = sections
        self.fontSize = fontSize
        self.scrollSpeed = scrollSpeed
    }

    // MARK: - Playback

    func togglePlayPause() {
        isPlaying.toggle()
    }

    func jumpForward() {
        if currentSectionIndex < sections.count - 1 {
            currentSectionIndex += 1
        }
    }

    func jumpBackward() {
        if currentSectionIndex > 0 {
            currentSectionIndex -= 1
        }
    }

    // MARK: - Speed

    func increaseSpeed() {
        scrollSpeed = min(Self.maxSpeed, scrollSpeed + Self.speedStep)
    }

    func decreaseSpeed() {
        scrollSpeed = max(Self.minSpeed, scrollSpeed - Self.speedStep)
    }

    // MARK: - Font size

    func increaseFontSize() {
        fontSize = min(Self.maxFontSize, fontSize + Self.fontSizeStep)
    }

    func decreaseFontSize() {
        fontSize = max(Self.minFontSize, fontSize - Self.fontSizeStep)
    }

    // MARK: - Opacity

    func increaseOpacity() {
        opacity = min(Self.maxOpacity, opacity + Self.opacityStep)
    }

    func decreaseOpacity() {
        opacity = max(Self.minOpacity, opacity - Self.opacityStep)
    }

    // MARK: - Click-through

    func toggleClickThrough() {
        isClickThrough.toggle()
    }

    // MARK: - Script Content

    var fullScriptText: String {
        sections.map(\.content).joined(separator: "\n\n")
    }

    /// Character index where each section starts in fullScriptText.
    var sectionStartIndices: [Int] {
        var indices: [Int] = []
        var offset = 0
        for (i, section) in sections.enumerated() {
            indices.append(offset)
            offset += section.content.count
            if i < sections.count - 1 {
                offset += 2 // "\n\n" separator
            }
        }
        return indices
    }

    /// Build state from a Script model.
    static func from(script: Script) -> TeleprompterState {
        let teleprompterSections = script.sortedSections.map { section in
            TeleprompterSection(
                slideNumber: section.slideNumber,
                label: section.label,
                content: section.content,
                accentColorHex: section.accentColorHex,
                thumbnailRelativePath: section.thumbnailRelativePath ?? ""
            )
        }
        // Migrate old multiplier format (0.25-3.0) to WPM (60-250)
        let wpm = script.scrollSpeed < 10 ? 160.0 : script.scrollSpeed
        let state = TeleprompterState(
            sections: teleprompterSections,
            fontSize: script.fontSize,
            scrollSpeed: wpm
        )
        state.sourceScript = script
        return state
    }
}
