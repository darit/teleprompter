import SwiftUI

struct ChatMessageView: View {
    let message: ChatMessage

    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 60) }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 8) {
                let segments = parseSegments(message.content)
                ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                    switch segment {
                    case .text(let text):
                        Text(attributedMarkdown(text))
                            .font(.system(size: 13))
                            .lineSpacing(4)
                            .textSelection(.enabled)
                            .padding(12)
                            .background {
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(message.role == .user
                                          ? Color.accentColor.opacity(0.08)
                                          : Color.primary.opacity(0.04))
                            }
                            .frame(maxWidth: 500, alignment: message.role == .user ? .trailing : .leading)

                    case .script(let slideNumber, let content):
                        scriptBlock(slideNumber: slideNumber, content: content)
                            .frame(maxWidth: 500, alignment: .leading)
                    }
                }
            }

            if message.role == .assistant { Spacer(minLength: 60) }
        }
    }

    private func scriptBlock(slideNumber: Int, content: String) -> some View {
        let accentColors = ["#4A9EFF", "#34C759", "#FF9500", "#FF2D55", "#AF52DE", "#5AC8FA", "#FFCC00", "#FF6B35"]
        let colorHex = accentColors[(slideNumber - 1) % accentColors.count]
        let color = Color(hex: colorHex) ?? .accentColor

        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                SlidePillView(slideNumber: slideNumber, colorHex: colorHex)
                Text("Script generated")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            Text(attributedMarkdown(content))
                .font(.system(size: 13))
                .lineSpacing(4)
                .textSelection(.enabled)
                .foregroundStyle(.primary.opacity(0.85))
        }
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: 12)
                .fill(color.opacity(0.06))
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(color.opacity(0.15), lineWidth: 1)
                }
        }
    }

    private func attributedMarkdown(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(text)
    }
}

// MARK: - Segment Parsing

private enum MessageSegment {
    case text(String)
    case script(slideNumber: Int, content: String)
}

private func parseSegments(_ text: String) -> [MessageSegment] {
    var segments: [MessageSegment] = []
    var remaining = text

    let startPattern = /\[SCRIPT_START\s+slide=(\d+)\]/
    let endMarker = "[SCRIPT_END]"

    while !remaining.isEmpty {
        if let match = remaining.firstMatch(of: startPattern) {
            let before = String(remaining[remaining.startIndex..<match.range.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !before.isEmpty {
                segments.append(.text(before))
            }

            let slideNumber = Int(match.1) ?? 1
            let afterStart = String(remaining[match.range.upperBound...])

            if let endRange = afterStart.range(of: endMarker) {
                let scriptContent = String(afterStart[afterStart.startIndex..<endRange.lowerBound])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                segments.append(.script(slideNumber: slideNumber, content: scriptContent))
                remaining = String(afterStart[endRange.upperBound...])
            } else {
                let scriptContent = afterStart.trimmingCharacters(in: .whitespacesAndNewlines)
                segments.append(.script(slideNumber: slideNumber, content: scriptContent))
                remaining = ""
            }
        } else {
            let text = remaining.trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                segments.append(.text(text))
            }
            remaining = ""
        }
    }

    if segments.isEmpty {
        segments.append(.text(text))
    }

    return segments
}

#Preview("Assistant with script block") {
    ChatMessageView(message: ChatMessage(role: .assistant, content: """
    Here's the script for your first slide:

    [SCRIPT_START slide=1]
    Good afternoon everyone. Today we'll review the **architecture changes** from Q1 and discuss what's ahead for the team.
    [SCRIPT_END]

    Now, for slide 2 -- can you tell me more about the performance improvements you mentioned?
    """))
    .padding()
}

#Preview("User message") {
    ChatMessageView(message: ChatMessage(role: .user, content: "I want to mention the team growth from 5 to 12 engineers."))
        .padding()
}
