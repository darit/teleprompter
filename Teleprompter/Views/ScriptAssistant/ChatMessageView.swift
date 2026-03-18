import SwiftUI

struct ChatMessageView: View {
    let message: ChatMessage
    let isLastAssistantMessage: Bool
    var onDelete: (() -> Void)?
    @State private var isHovered = false

    init(message: ChatMessage, isLastAssistantMessage: Bool = false, onDelete: (() -> Void)? = nil) {
        self.message = message
        self.isLastAssistantMessage = isLastAssistantMessage
        self.onDelete = onDelete
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Role label
            Text(message.role == .user ? "You" : "Assistant")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)

            // Message content
            if message.role == .user {
                Text(message.content)
                    .font(.system(size: 15))
                    .lineSpacing(6)
                    .textSelection(.enabled)
            } else {
                let segments = parseSegments(message.content)
                ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                    switch segment {
                    case .text(let text):
                        MarkdownContentView(text: text)

                    case .script(let slideNumber, let content):
                        scriptBlock(slideNumber: slideNumber, content: content)
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .overlay(alignment: .topTrailing) {
            if isHovered {
                messageActions
                    .transition(.opacity)
            }
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }

    private var messageActions: some View {
        HStack(spacing: 4) {
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(message.content, forType: .string)
            } label: {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Copy message")

            if message.role == .assistant && isLastAssistantMessage {
                Button {
                    NotificationCenter.default.post(
                        name: .regenerateLastResponse, object: nil
                    )
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Regenerate response")
            }

            if let onDelete {
                Button {
                    onDelete()
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Delete message")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .glassEffect(.regular.interactive(), in: .capsule)
        .padding(8)
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
                .font(.system(size: 14))
                .lineSpacing(5)
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

extension Notification.Name {
    static let regenerateLastResponse = Notification.Name("regenerateLastResponse")
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
    """), isLastAssistantMessage: true)
    .padding()
}

#Preview("User message") {
    ChatMessageView(message: ChatMessage(role: .user, content: "I want to mention the team growth from 5 to 12 engineers."))
        .padding()
}
