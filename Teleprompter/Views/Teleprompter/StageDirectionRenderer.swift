import SwiftUI

enum StageDirectionRenderer {

    /// Known stage direction markers and their display properties.
    private static let directions: [(pattern: String, icon: String)] = [
        ("[PAUSE]", "pause.fill"),
        ("[SLOW]", "tortoise.fill"),
        ("[LOOK AT CAMERA]", "eye.fill"),
        ("[SHOW SLIDE]", "rectangle.on.rectangle.angled"),
        ("[BREATHE]", "wind"),
    ]

    /// Renders text with inline markdown and stage direction badges (concatenated Text views).
    /// Use in the teleprompter where rich rendering is needed and view count is small.
    static func render(_ content: String) -> Text {
        let segments = parseSegments(content)

        var result = Text("")
        for segment in segments {
            switch segment {
            case .text(let str):
                let attributed = (try? AttributedString(
                    markdown: str,
                    options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
                )) ?? AttributedString(str)
                result = result + Text(attributed)

            case .direction(let label, let icon):
                result = result
                    + Text("  ")
                    + Text("\(Image(systemName: icon)) \(label)")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundColor(.yellow.opacity(0.9))
                    + Text("  ")
            }
        }

        return result
    }

    /// Renders text as a single AttributedString with stage directions as styled inline text.
    /// Use in lists/scroll views where layout performance matters (avoids deep Text concatenation).
    static func renderAttributedString(_ content: String) -> AttributedString {
        let segments = parseSegments(content)

        var result = AttributedString()
        for segment in segments {
            switch segment {
            case .text(let str):
                let attributed = (try? AttributedString(
                    markdown: str,
                    options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
                )) ?? AttributedString(str)
                result += attributed

            case .direction(let label, _):
                var marker = AttributedString("  \(label)  ")
                marker.foregroundColor = .yellow.opacity(0.9)
                marker.font = .system(size: 11, weight: .semibold, design: .rounded)
                result += marker
            }
        }

        return result
    }

    // MARK: - Parsing

    private enum Segment {
        case text(String)
        case direction(label: String, icon: String)
    }

    private static func parseSegments(_ content: String) -> [Segment] {
        var segments: [Segment] = []
        var remaining = content

        while !remaining.isEmpty {
            // Find the earliest stage direction match
            var earliest: (range: Range<String.Index>, label: String, icon: String)?

            for (pattern, icon) in directions {
                if let range = remaining.range(of: pattern, options: .caseInsensitive) {
                    if earliest == nil || range.lowerBound < earliest!.range.lowerBound {
                        let label = pattern
                            .replacingOccurrences(of: "[", with: "")
                            .replacingOccurrences(of: "]", with: "")
                        earliest = (range, label, icon)
                    }
                }
            }

            // Also check for any unknown [DIRECTION] patterns (exclude script markers)
            if earliest == nil {
                let bracketPattern = /\[([A-Z][A-Z\s]{1,20})\]/
                if let match = remaining.firstMatch(of: bracketPattern) {
                    let label = String(match.1)
                    let skip = label.hasPrefix("SCRIPT_START") || label.hasPrefix("SCRIPT_END")
                    if !skip {
                        earliest = (match.range, label, "text.bubble")
                    }
                }
            }

            if let match = earliest {
                let before = String(remaining[remaining.startIndex..<match.range.lowerBound])
                if !before.isEmpty {
                    segments.append(.text(before))
                }
                segments.append(.direction(label: match.label, icon: match.icon))
                remaining = String(remaining[match.range.upperBound...])
            } else {
                segments.append(.text(remaining))
                remaining = ""
            }
        }

        return segments
    }
}
