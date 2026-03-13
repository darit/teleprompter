import SwiftUI

struct MarkdownContentView: View {
    let text: String

    var body: some View {
        let blocks = Self.parseBlocks(text)
        VStack(alignment: .leading, spacing: 12) {
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
            options: .init(interpretedSyntax: .full)
        )) ?? AttributedString(text)
    }
}

// MARK: - Block Parsing

enum MarkdownBlock {
    case text(String)
    case codeBlock(language: String?, code: String)
    case heading(level: Int, content: String)
    case blockquote(String)
}

extension MarkdownContentView {
    static func parseBlocks(_ text: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        let lines = text.components(separatedBy: "\n")
        var currentText: [String] = []
        var inCodeBlock = false
        var codeLanguage: String?
        var codeLines: [String] = []

        for line in lines {
            if line.hasPrefix("```") && !inCodeBlock {
                let textContent = currentText.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                if !textContent.isEmpty {
                    blocks.append(.text(textContent))
                }
                currentText = []
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
            } else if line.hasPrefix("#### ") {
                let textContent = currentText.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                if !textContent.isEmpty { blocks.append(.text(textContent)) }
                currentText = []
                blocks.append(.heading(level: 4, content: String(line.dropFirst(5))))
            } else if line.hasPrefix("### ") {
                let textContent = currentText.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                if !textContent.isEmpty { blocks.append(.text(textContent)) }
                currentText = []
                blocks.append(.heading(level: 3, content: String(line.dropFirst(4))))
            } else if line.hasPrefix("## ") {
                let textContent = currentText.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                if !textContent.isEmpty { blocks.append(.text(textContent)) }
                currentText = []
                blocks.append(.heading(level: 2, content: String(line.dropFirst(3))))
            } else if line.hasPrefix("# ") {
                let textContent = currentText.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                if !textContent.isEmpty { blocks.append(.text(textContent)) }
                currentText = []
                blocks.append(.heading(level: 1, content: String(line.dropFirst(2))))
            } else if line.hasPrefix("> ") {
                let textContent = currentText.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                if !textContent.isEmpty { blocks.append(.text(textContent)) }
                currentText = []
                blocks.append(.blockquote(String(line.dropFirst(2))))
            } else {
                currentText.append(line)
            }
        }

        if inCodeBlock {
            blocks.append(.codeBlock(language: codeLanguage, code: codeLines.joined(separator: "\n")))
        }

        let remaining = currentText.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        if !remaining.isEmpty {
            blocks.append(.text(remaining))
        }

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
