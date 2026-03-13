import SwiftUI

struct MarkdownContentView: View {
    let text: String

    var body: some View {
        let blocks = Self.parseBlocks(text)
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                switch block {
                case .text(let content):
                    Text(Self.attributedMarkdown(content))
                        .font(.system(size: 15))
                        .lineSpacing(6)
                        .textSelection(.enabled)

                case .codeBlock(let language, let code):
                    codeBlockView(language: language, code: code)

                case .heading(let level, let content):
                    Text(content)
                        .font(.system(size: headingSize(level), weight: .semibold))
                        .padding(.top, 4)

                case .blockquote(let content):
                    HStack(spacing: 0) {
                        Rectangle()
                            .fill(Color.secondary.opacity(0.3))
                            .frame(width: 3)

                        Text(Self.attributedMarkdown(content))
                            .font(.system(size: 15))
                            .lineSpacing(6)
                            .foregroundStyle(.secondary)
                            .padding(.leading, 12)
                    }

                case .horizontalRule:
                    Divider()
                        .padding(.vertical, 4)
                }
            }
        }
    }

    private func codeBlockView(language: String?, code: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if let language, !language.isEmpty {
                HStack {
                    Text(language)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(code, forType: .string)
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Copy code")
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)

                Divider()
            }

            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(.system(size: 13, design: .monospaced))
                    .lineSpacing(4)
                    .textSelection(.enabled)
                    .padding(12)
            }
        }
        .background {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(.textBackgroundColor).opacity(0.5))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(nsColor: .quaternaryLabelColor), lineWidth: 0.5)
        }
    }

    private func headingSize(_ level: Int) -> CGFloat {
        switch level {
        case 1, 2: return 20
        case 3: return 17
        default: return 15
        }
    }

    static func attributedMarkdown(_ text: String) -> AttributedString {
        (try? AttributedString(
            markdown: text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(text)
    }
}

// MARK: - Block Parsing

enum MarkdownBlock {
    case text(String)
    case codeBlock(language: String?, code: String)
    case heading(level: Int, content: String)
    case blockquote(String)
    case horizontalRule
}

extension MarkdownContentView {

    /// Matches markdown horizontal rules: `---`, `***`, `___` (3+ chars), or the Unicode em dash `\u{2E3B}`
    private static func isHorizontalRule(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.allSatisfy({ $0 == "\u{2014}" || $0 == "\u{2E3A}" || $0 == "\u{2E3B}" }) && !trimmed.isEmpty {
            return true
        }
        guard trimmed.count >= 3 else { return false }
        let unique = Set(trimmed)
        return unique.count == 1 && (unique.contains("-") || unique.contains("*") || unique.contains("_"))
    }

    private static func flushText(_ currentText: inout [String], into blocks: inout [MarkdownBlock]) {
        let joined = currentText.joined(separator: "\n")
        currentText = []

        // Split on blank lines to create separate paragraphs
        let paragraphs = joined.components(separatedBy: "\n\n")
        for paragraph in paragraphs {
            let trimmed = paragraph.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                blocks.append(.text(trimmed))
            }
        }
    }

    static func parseBlocks(_ text: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        let lines = text.components(separatedBy: "\n")
        var currentText: [String] = []
        var inCodeBlock = false
        var codeLanguage: String?
        var codeLines: [String] = []
        var blockquoteLines: [String] = []

        for line in lines {
            if line.hasPrefix("```") && !inCodeBlock {
                flushText(&currentText, into: &blocks)
                if !blockquoteLines.isEmpty {
                    blocks.append(.blockquote(blockquoteLines.joined(separator: "\n")))
                    blockquoteLines = []
                }
                inCodeBlock = true
                let lang = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                codeLanguage = lang.isEmpty ? nil : lang
                codeLines = []
            } else if line.hasPrefix("```") && inCodeBlock {
                blocks.append(.codeBlock(language: codeLanguage, code: codeLines.joined(separator: "\n")))
                inCodeBlock = false
                codeLanguage = nil
                codeLines = []
            } else if inCodeBlock {
                codeLines.append(line)
            } else if isHorizontalRule(line) {
                flushText(&currentText, into: &blocks)
                if !blockquoteLines.isEmpty {
                    blocks.append(.blockquote(blockquoteLines.joined(separator: "\n")))
                    blockquoteLines = []
                }
                blocks.append(.horizontalRule)
            } else if line.hasPrefix("> ") || line == ">" {
                flushText(&currentText, into: &blocks)
                let content = line.hasPrefix("> ") ? String(line.dropFirst(2)) : ""
                blockquoteLines.append(content)
            } else {
                // Flush any accumulated blockquote
                if !blockquoteLines.isEmpty {
                    blocks.append(.blockquote(blockquoteLines.joined(separator: "\n")))
                    blockquoteLines = []
                }

                if line.hasPrefix("#### ") {
                    flushText(&currentText, into: &blocks)
                    blocks.append(.heading(level: 4, content: String(line.dropFirst(5))))
                } else if line.hasPrefix("### ") {
                    flushText(&currentText, into: &blocks)
                    blocks.append(.heading(level: 3, content: String(line.dropFirst(4))))
                } else if line.hasPrefix("## ") {
                    flushText(&currentText, into: &blocks)
                    blocks.append(.heading(level: 2, content: String(line.dropFirst(3))))
                } else if line.hasPrefix("# ") {
                    flushText(&currentText, into: &blocks)
                    blocks.append(.heading(level: 1, content: String(line.dropFirst(2))))
                } else {
                    currentText.append(line)
                }
            }
        }

        if inCodeBlock {
            blocks.append(.codeBlock(language: codeLanguage, code: codeLines.joined(separator: "\n")))
        }

        if !blockquoteLines.isEmpty {
            blocks.append(.blockquote(blockquoteLines.joined(separator: "\n")))
        }

        flushText(&currentText, into: &blocks)

        if blocks.isEmpty {
            blocks.append(.text(text))
        }

        return blocks
    }
}

#Preview {
    MarkdownContentView(text: """
    Here is some **bold** and *italic* text.

    ### A Heading

    - First item
    - Second item
    - Third item

    ```swift
    let greeting = "Hello, world!"
    print(greeting)
    ```

    > This is a blockquote

    Regular paragraph continues here.
    """)
    .padding()
    .frame(width: 500)
}
