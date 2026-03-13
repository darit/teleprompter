# Script Assistant Window UX Redesign Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Redesign the Script Assistant chat window with flat layout, live streaming preview, markdown rendering, message actions, and improved sizing for readability.

**Architecture:** Modify existing views (ScriptAssistantView, ChatPanelView, ChatMessageView) to use flat full-width message layout with role labels. Add cancellation support to ConversationManager and providers. Add new small components (TypingIndicatorView, ScrollToBottomButton, MarkdownContentView). Enhance ScriptPreviewPanel with active-slide tracking.

**Tech Stack:** SwiftUI (macOS 14+), Swift Testing, SwiftData

---

## File Structure

| File | Responsibility |
|------|----------------|
| `Teleprompter/Views/ScriptAssistant/ScriptAssistantView.swift` | Window sizing, top bar layout |
| `Teleprompter/Views/ScriptAssistant/ChatPanelView.swift` | Message list, input area, scroll-to-bottom, stop button |
| `Teleprompter/Views/ScriptAssistant/ChatMessageView.swift` | Flat message layout, role labels, hover actions, markdown |
| `Teleprompter/Views/ScriptAssistant/TypingIndicatorView.swift` | Three-dot pulsing animation (new) |
| `Teleprompter/Views/ScriptAssistant/MarkdownContentView.swift` | Block-level markdown rendering with code blocks (new) |
| `Teleprompter/Services/ConversationManager.swift` | Cancellation, regenerate, live script parsing, activelyStreamingSlideNumber |
| `Teleprompter/LLM/ClaudeCLIProvider.swift` | Store Process ref for cancellation |
| `Teleprompter/Views/ScriptAssistant/ScriptPreviewPanel.swift` | Pulsing indicator on active slide, auto-scroll |
| `TeleprompterTests/Services/ConversationManagerTests.swift` | Tests for cancellation, regenerate, live parsing |
| `TeleprompterTests/Helpers/MockLLMProvider.swift` | Mock provider for tests (new) |
| `Teleprompter/Views/ScriptManager/ScriptManagerView.swift:44` | Update sheet frame to 960x720 |

---

## Chunk 1: ConversationManager Cancellation & Regenerate

### Task 0: Create test infrastructure

**Files:**
- Create: `TeleprompterTests/Helpers/MockLLMProvider.swift`
- Modify: `TeleprompterTests/Services/ConversationManagerTests.swift`

- [ ] **Step 1: Create MockLLMProvider**

```swift
// TeleprompterTests/Helpers/MockLLMProvider.swift
import Foundation
@testable import Teleprompter

final class MockLLMProvider: LLMProvider, @unchecked Sendable {
    var displayName: String = "Mock Provider"
    var isAvailable: Bool = true

    var streamResponse: [String] = []

    func stream(messages: [ChatMessage]) async throws -> AsyncStream<String> {
        let chunks = streamResponse
        return AsyncStream { continuation in
            for chunk in chunks {
                continuation.yield(chunk)
            }
            continuation.finish()
        }
    }
}
```

- [ ] **Step 2: Add makeTestInstance helper to ConversationManagerTests**

At the bottom of `ConversationManagerTests.swift`, add:

```swift
import SwiftData

extension ConversationManager {
    @MainActor
    static func makeTestInstance(
        provider: LLMProvider? = nil,
        slides: [SlideContent] = []
    ) -> ConversationManager {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(
            for: Script.self, PersistedChatMessage.self, ScriptSection.self,
            configurations: config
        )
        let context = ModelContext(container)
        let script = Script(title: "Test Script", sections: [])
        context.insert(script)
        return ConversationManager(
            provider: provider ?? MockLLMProvider(),
            slides: slides,
            script: script,
            modelContext: context
        )
    }
}
```

- [ ] **Step 3: Build tests to verify infrastructure compiles**

Run: `xcodebuild build-for-testing -scheme Teleprompter -destination 'platform=macOS' 2>&1 | tail -20`
Expected: BUILD SUCCEEDED

- [ ] **Step 4: Commit**

```bash
git add TeleprompterTests/Helpers/MockLLMProvider.swift TeleprompterTests/Services/ConversationManagerTests.swift
git commit -m "Add test infrastructure for ConversationManager instance tests"
```

### Task 1: Add cancellation support to ConversationManager

**Files:**
- Modify: `Teleprompter/Services/ConversationManager.swift`
- Test: `TeleprompterTests/Services/ConversationManagerTests.swift`

- [ ] **Step 1: Write failing test for stopStreaming**

In `TeleprompterTests/Services/ConversationManagerTests.swift`, add:

```swift
@Test("stopStreaming finalizes partial text as assistant message")
@MainActor
func testStopStreaming() async {
    let manager = ConversationManager.makeTestInstance()

    // Simulate streaming state
    manager.isStreaming = true
    manager.currentStreamingText = "Partial response text"

    manager.stopStreaming()

    #expect(manager.isStreaming == false)
    #expect(manager.currentStreamingText.isEmpty)
    // The partial text should have been appended as an assistant message
    let lastVisible = manager.visibleMessages.last
    #expect(lastVisible?.role == .assistant)
    #expect(lastVisible?.content == "Partial response text")
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme Teleprompter -destination 'platform=macOS' -only-testing TeleprompterTests/ConversationManagerTests/testStopStreaming 2>&1 | tail -20`
Expected: FAIL -- `stopStreaming` method does not exist.

- [ ] **Step 3: Implement stopStreaming and Task storage in ConversationManager**

In `Teleprompter/Services/ConversationManager.swift`:

Add a stored property for the streaming task:

```swift
private var streamingTask: Task<Void, Never>?
```

Add the `stopStreaming` method:

```swift
@MainActor
func stopStreaming() {
    streamingTask?.cancel()
    streamingTask = nil

    if isStreaming {
        let partial = currentStreamingText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !partial.isEmpty {
            let assistantMsg = ChatMessage(role: .assistant, content: partial)
            messages.append(assistantMsg)
            persistMessage(assistantMsg)

            // Parse any script markers in the partial response
            let segments = Self.parseResponse(partial)
            for segment in segments {
                if case .script(let slideNumber) = segment.type {
                    updateScriptSection(slideNumber: slideNumber, content: segment.content)
                }
            }
        }
        currentStreamingText = ""
        isStreaming = false
    }
}
```

Modify `streamResponse()` to store the task reference. Wrap the streaming loop in a cancellation-aware pattern:

```swift
@MainActor
private func streamResponse() async {
    isStreaming = true
    currentStreamingText = ""
    error = nil

    streamingTask = Task {
        do {
            let stream = try await provider.stream(messages: messages)

            for await chunk in stream {
                if Task.isCancelled { break }
                currentStreamingText += chunk
            }

            guard !Task.isCancelled else { return }

            let response = currentStreamingText.trimmingCharacters(in: .whitespacesAndNewlines)
            let assistantMsg = ChatMessage(role: .assistant, content: response)
            messages.append(assistantMsg)
            persistMessage(assistantMsg)

            let segments = Self.parseResponse(response)
            for segment in segments {
                if case .script(let slideNumber) = segment.type {
                    updateScriptSection(slideNumber: slideNumber, content: segment.content)
                }
            }

            currentStreamingText = ""
        } catch {
            if !Task.isCancelled {
                self.error = error.localizedDescription
            }
        }

        isStreaming = false
    }

    await streamingTask?.value
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -scheme Teleprompter -destination 'platform=macOS' -only-testing TeleprompterTests/ConversationManagerTests/testStopStreaming 2>&1 | tail -20`
Expected: PASS

- [ ] **Step 5: Run all existing tests to confirm no regressions**

Run: `xcodebuild test -scheme Teleprompter -destination 'platform=macOS' 2>&1 | tail -30`
Expected: All tests pass.

- [ ] **Step 6: Commit**

```bash
git add Teleprompter/Services/ConversationManager.swift TeleprompterTests/Services/ConversationManagerTests.swift
git commit -m "Add streaming cancellation support to ConversationManager"
```

### Task 2: Add regenerate support to ConversationManager

**Files:**
- Modify: `Teleprompter/Services/ConversationManager.swift`
- Test: `TeleprompterTests/Services/ConversationManagerTests.swift`

- [ ] **Step 1: Write failing test for regenerateLastResponse**

```swift
@Test("regenerateLastResponse removes last assistant message")
func testRegenerateRemovesLastAssistant() {
    let manager = ConversationManager.makeTestInstance()

    // Add a user message and an assistant message
    let userMsg = ChatMessage(role: .user, content: "Write slide 1")
    let assistantMsg = ChatMessage(role: .assistant, content: "Here is slide 1 content")
    manager.messages.append(userMsg)
    manager.messages.append(assistantMsg)

    let countBefore = manager.messages.count
    manager.removeLastAssistantMessage()

    #expect(manager.messages.count == countBefore - 1)
    #expect(manager.messages.last?.role == .user)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme Teleprompter -destination 'platform=macOS' -only-testing TeleprompterTests/ConversationManagerTests/testRegenerateRemovesLastAssistant 2>&1 | tail -20`
Expected: FAIL

- [ ] **Step 3: Implement removeLastAssistantMessage**

In `ConversationManager.swift`:

```swift
@MainActor
func removeLastAssistantMessage() {
    guard let lastIndex = messages.lastIndex(where: { $0.role == .assistant }) else { return }
    let removedMessage = messages.remove(at: lastIndex)

    // Remove last persisted assistant message
    if let lastPersisted = script.chatHistory
        .sorted(by: { $0.order < $1.order })
        .last(where: { $0.role == "assistant" }) {
        modelContext.delete(lastPersisted)
        script.chatHistory.removeAll { $0 === lastPersisted }
    }

    // Clear any ScriptSections generated from the removed response
    let segments = Self.parseResponse(removedMessage.content)
    for segment in segments {
        if case .script(let slideNumber) = segment.type {
            if let section = script.sections.first(where: { $0.slideNumber == slideNumber }) {
                section.content = ""
            }
        }
    }
}

@MainActor
func regenerateLastResponse() async {
    removeLastAssistantMessage()
    await streamResponse()
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -scheme Teleprompter -destination 'platform=macOS' -only-testing TeleprompterTests/ConversationManagerTests/testRegenerateRemovesLastAssistant 2>&1 | tail -20`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Teleprompter/Services/ConversationManager.swift TeleprompterTests/Services/ConversationManagerTests.swift
git commit -m "Add regenerate support to ConversationManager"
```

### Task 3: Add activelyStreamingSlideNumber for live preview tracking

**Files:**
- Modify: `Teleprompter/Services/ConversationManager.swift`
- Test: `TeleprompterTests/Services/ConversationManagerTests.swift`

- [ ] **Step 1: Write failing test for live script marker parsing**

```swift
@Test("parseStreamingChunk detects script markers incrementally")
func testParseStreamingChunkDetectsMarkers() {
    // Test the buffered parsing logic
    var buffer = ""

    // Simulate chunks arriving
    buffer += "Here is the script:\n\n"
    let result1 = ConversationManager.parseStreamingBuffer(buffer)
    #expect(result1.activeSlideNumber == nil)

    buffer += "[SCRIPT_START slide=2]\nSome content"
    let result2 = ConversationManager.parseStreamingBuffer(buffer)
    #expect(result2.activeSlideNumber == 2)
    #expect(result2.partialContent == "Some content")
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme Teleprompter -destination 'platform=macOS' -only-testing TeleprompterTests/ConversationManagerTests/testParseStreamingChunkDetectsMarkers 2>&1 | tail -20`
Expected: FAIL

- [ ] **Step 3: Implement parseStreamingBuffer and activelyStreamingSlideNumber**

In `ConversationManager.swift`, add the published property and static parser:

```swift
// Add to class properties
var activelyStreamingSlideNumber: Int?

struct StreamingParseResult {
    let activeSlideNumber: Int?
    let partialContent: String?
}

static func parseStreamingBuffer(_ buffer: String) -> StreamingParseResult {
    let startPattern = /\[SCRIPT_START\s+slide=(\d+)\]/
    let endMarker = "[SCRIPT_END]"

    // Find the last unclosed SCRIPT_START marker
    var lastSlideNumber: Int?
    var lastStartEnd: String.Index?
    var remaining = buffer[buffer.startIndex...]

    while let match = remaining.firstMatch(of: startPattern) {
        lastSlideNumber = Int(match.1)
        lastStartEnd = match.range.upperBound
        remaining = remaining[match.range.upperBound...]
    }

    guard let slideNumber = lastSlideNumber, let contentStart = lastStartEnd else {
        return StreamingParseResult(activeSlideNumber: nil, partialContent: nil)
    }

    let afterStart = String(buffer[contentStart...])

    // Check if this block is already closed
    if afterStart.contains(endMarker) {
        return StreamingParseResult(activeSlideNumber: nil, partialContent: nil)
    }

    let partialContent = afterStart.trimmingCharacters(in: .whitespacesAndNewlines)
    return StreamingParseResult(activeSlideNumber: slideNumber, partialContent: partialContent.isEmpty ? nil : partialContent)
}
```

Update the streaming loop in `streamResponse()` to call this parser on each chunk and update `activelyStreamingSlideNumber`:

```swift
// Inside the for await chunk in stream loop, after currentStreamingText += chunk:
let parseResult = Self.parseStreamingBuffer(currentStreamingText)
activelyStreamingSlideNumber = parseResult.activeSlideNumber
if let slideNum = parseResult.activeSlideNumber, let partial = parseResult.partialContent {
    updateScriptSection(slideNumber: slideNum, content: partial)
}
```

Clear `activelyStreamingSlideNumber` at the end of streaming (in both normal completion and `stopStreaming`):

```swift
activelyStreamingSlideNumber = nil
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -scheme Teleprompter -destination 'platform=macOS' -only-testing TeleprompterTests/ConversationManagerTests/testParseStreamingChunkDetectsMarkers 2>&1 | tail -20`
Expected: PASS

- [ ] **Step 5: Run all tests**

Run: `xcodebuild test -scheme Teleprompter -destination 'platform=macOS' 2>&1 | tail -30`
Expected: All pass.

- [ ] **Step 6: Commit**

```bash
git add Teleprompter/Services/ConversationManager.swift TeleprompterTests/Services/ConversationManagerTests.swift
git commit -m "Add live script marker parsing during streaming"
```

---

## Chunk 2: New Components (must exist before views reference them)

### Task 4: Create TypingIndicatorView

**Files:**
- Create: `Teleprompter/Views/ScriptAssistant/TypingIndicatorView.swift`

- [ ] **Step 1: Create the typing indicator component**

```swift
// Teleprompter/Views/ScriptAssistant/TypingIndicatorView.swift
import SwiftUI

struct TypingIndicatorView: View {
    @State private var animating = false

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(Color.secondary)
                    .frame(width: 6, height: 6)
                    .opacity(animating ? 0.7 : 0.2)
                    .animation(
                        .easeInOut(duration: 0.6)
                        .repeatForever(autoreverses: true)
                        .delay(Double(index) * 0.2),
                        value: animating
                    )
            }
        }
        .onAppear {
            animating = true
        }
    }
}

#Preview {
    TypingIndicatorView()
        .padding()
}
```

- [ ] **Step 2: Build to verify**

Run: `xcodebuild build -scheme Teleprompter -destination 'platform=macOS' 2>&1 | tail -20`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add Teleprompter/Views/ScriptAssistant/TypingIndicatorView.swift
git commit -m "Add animated typing indicator component"
```

### Task 5: Create MarkdownContentView

**Files:**
- Create: `Teleprompter/Views/ScriptAssistant/MarkdownContentView.swift`

- [ ] **Step 1: Create block-level markdown rendering view**

```swift
// Teleprompter/Views/ScriptAssistant/MarkdownContentView.swift
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
                .stroke(Color.quaternary, lineWidth: 0.5)
        }
    }

    private func headingSize(_ level: Int) -> CGFloat {
        switch level {
        case 1, 2: return 20
        case 3: return 17
        default: return 15
        }
    }

    /// Use `.full` interpreted syntax for proper list rendering.
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

        // Handle unclosed code block (streaming safety)
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
```

Note: `parseBlocks` is `static` and `MarkdownBlock` is `internal` for testability, following the same pattern as `ConversationManager.parseResponse`. Heading detection checks `####` before `###` before `##` before `#` to avoid false matches on longer prefixes. Lists (bullet and numbered) are handled by `AttributedString(markdown:, interpretedSyntax: .full)` within text blocks -- the parser passes them through as text and the full markdown interpreter renders them with proper indentation.

- [ ] **Step 2: Build to verify**

Run: `xcodebuild build -scheme Teleprompter -destination 'platform=macOS' 2>&1 | tail -20`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add Teleprompter/Views/ScriptAssistant/MarkdownContentView.swift
git commit -m "Add block-level markdown rendering with code blocks and headings"
```

---

## Chunk 3: Window Layout & Flat Message Design

### Task 6: Update window sizing and top bar layout

**Files:**
- Modify: `Teleprompter/Views/ScriptAssistant/ScriptAssistantView.swift`
- Modify: `Teleprompter/Views/ScriptManager/ScriptManagerView.swift:44`

- [ ] **Step 1: Update window frame constraints**

In `ScriptAssistantView.swift` line 105, change the frame modifier on the root VStack:

```swift
.frame(minWidth: 800, minHeight: 600)
```

Update the HSplitView panel widths (lines 90 and 102):

```swift
// Chat panel (line 90)
.frame(minWidth: 400, idealWidth: 480)

// Script preview panel (line 102)
.frame(minWidth: 350, idealWidth: 400)
```

In `Teleprompter/Views/ScriptManager/ScriptManagerView.swift` line 44, update the sheet frame:

```swift
.frame(minWidth: 800, idealWidth: 960, minHeight: 600, idealHeight: 720)
```

- [ ] **Step 2: Reorganize top bar -- title left, provider+duration center, actions right**

Replace the existing top bar HStack in `ScriptAssistantView.swift` lines 24-82:

```swift
HStack(spacing: 16) {
    Text("Script Assistant")
        .font(.system(size: 13, weight: .semibold))

    Spacer()

    HStack(spacing: 12) {
        Picker("", selection: $selectedProvider) {
            ForEach(ProviderChoice.allCases, id: \.self) { choice in
                Text(choice.rawValue).tag(choice)
            }
        }
        .pickerStyle(.menu)
        .frame(width: 170)
        .onChange(of: selectedProvider) {
            switchProvider()
        }

        Picker("", selection: $targetMinutes) {
            Text("5 min").tag(5)
            Text("10 min").tag(10)
            Text("15 min").tag(15)
            Text("20 min").tag(20)
            Text("30 min").tag(30)
            Text("45 min").tag(45)
            Text("60 min").tag(60)
        }
        .frame(width: 80)
        .onChange(of: targetMinutes) {
            script.targetDuration = Double(targetMinutes)
        }
    }

    Spacer()

    HStack(spacing: 8) {
        Button {
            conversation?.clearHistory()
        } label: {
            Image(systemName: "trash")
                .font(.system(size: 11))
        }
        .buttonStyle(.plain)
        .help("Clear chat history")
        .disabled(conversation?.visibleMessages.isEmpty ?? true)

        Button("Done") {
            dismiss()
        }
        .buttonStyle(.glass)
    }
}
.padding(.horizontal, 16)
.padding(.vertical, 10)
.background(.ultraThinMaterial)
```

- [ ] **Step 3: Build to verify no compilation errors**

Run: `xcodebuild build -scheme Teleprompter -destination 'platform=macOS' 2>&1 | tail -20`
Expected: BUILD SUCCEEDED

- [ ] **Step 4: Commit**

```bash
git add Teleprompter/Views/ScriptAssistant/ScriptAssistantView.swift Teleprompter/Views/ScriptManager/ScriptManagerView.swift
git commit -m "Update window sizing and reorganize top bar layout"
```

### Task 7: Redesign ChatMessageView with flat layout

**Files:**
- Modify: `Teleprompter/Views/ScriptAssistant/ChatMessageView.swift`

- [ ] **Step 1: Replace bubble layout with flat full-width layout**

Rewrite `ChatMessageView.body`:

```swift
struct ChatMessageView: View {
    let message: ChatMessage
    let isLastAssistantMessage: Bool
    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Role label
            Text(message.role == .user ? "You" : "Assistant")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)

            // Message content
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
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
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
                }
                .buttonStyle(.plain)
                .help("Regenerate response")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background {
            Capsule()
                .fill(.ultraThinMaterial)
        }
        .padding(8)
    }
}
```

Note: The regenerate button uses `NotificationCenter` to communicate back to `ChatPanelView`. Define the notification name:

```swift
extension Notification.Name {
    static let regenerateLastResponse = Notification.Name("regenerateLastResponse")
}
```

Add an `isLastAssistantMessage` computed property or pass it from the parent. The simplest approach: pass it as a parameter from ChatPanelView's ForEach.

- [ ] **Step 2: Update the scriptBlock method**

Keep the existing `scriptBlock` method but update font size:

```swift
private func scriptBlock(slideNumber: Int, content: String) -> some View {
    // Keep existing implementation but change font to 14pt and line spacing to 5
    // ...existing code with .font(.system(size: 14)) and .lineSpacing(5)
}
```

- [ ] **Step 3: Remove the old bubble-related code**

Remove: `Spacer(minLength: 60)`, `.frame(maxWidth: 500)`, the bubble background `RoundedRectangle` fills for text segments, and the left/right alignment logic.

- [ ] **Step 4: Build to verify**

Run: `xcodebuild build -scheme Teleprompter -destination 'platform=macOS' 2>&1 | tail -20`
Expected: BUILD SUCCEEDED

- [ ] **Step 5: Commit**

```bash
git add Teleprompter/Views/ScriptAssistant/ChatMessageView.swift
git commit -m "Redesign chat messages with flat full-width layout and hover actions"
```

### Task 6: Update ChatPanelView with new layout, input, and stop button

**Files:**
- Modify: `Teleprompter/Views/ScriptAssistant/ChatPanelView.swift`

- [ ] **Step 1: Update message list spacing and separators**

In `ChatPanelView.swift`, update the LazyVStack:

```swift
LazyVStack(spacing: 0) {
    ForEach(Array(conversation.visibleMessages.enumerated()), id: \.element.id) { index, message in
        let isLastAssistant = message.role == .assistant &&
            message.id == conversation.visibleMessages.last(where: { $0.role == .assistant })?.id

        ChatMessageView(message: message, isLastAssistantMessage: isLastAssistant)

        // Separator between messages
        if index < conversation.visibleMessages.count - 1 {
            Divider()
                .foregroundStyle(.quaternary)
                .padding(.horizontal, 16)
        }
    }

    if conversation.isStreaming {
        Divider()
            .foregroundStyle(.quaternary)
            .padding(.horizontal, 16)
        streamingMessageView
            .id("streaming")
    }

    Color.clear
        .frame(height: 1)
        .id("bottom")
}
.padding(.vertical, 12)
```

- [ ] **Step 2: Replace streamingBubble with flat streaming view**

Replace the `streamingBubble` computed property:

```swift
private var streamingMessageView: some View {
    VStack(alignment: .leading, spacing: 6) {
        Text("Assistant")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)

        if conversation.currentStreamingText.isEmpty {
            TypingIndicatorView()
        } else {
            HStack(spacing: 0) {
                MarkdownContentView(text: conversation.currentStreamingText)

                // Blinking cursor
                BlinkingCursorView()
            }
        }
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 12)
    .frame(maxWidth: .infinity, alignment: .leading)
}
```

Add a small `BlinkingCursorView` inside `ChatPanelView.swift` (or as a private view):

```swift
private struct BlinkingCursorView: View {
    @State private var visible = true

    var body: some View {
        Rectangle()
            .fill(Color.primary)
            .frame(width: 2, height: 16)
            .opacity(visible ? 1 : 0)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.53).repeatForever(autoreverses: true)) {
                    visible = false
                }
            }
    }
}
```

Trigger the cursor animation in `.onAppear` of the cursor view or use a `TimelineView`.

- [ ] **Step 3: Redesign input area with send/stop toggle**

Replace the input bar:

```swift
// Input bar
VStack(spacing: 0) {
    Divider()

    HStack(alignment: .bottom, spacing: 8) {
        TextField("Ask about your script...", text: $inputText, axis: .vertical)
            .textFieldStyle(.plain)
            .lineLimit(1...8)
            .font(.system(size: 14))
            .focused($isInputFocused)
            .onKeyPress(.return) {
                if NSEvent.modifierFlags.contains(.shift) {
                    return .ignored  // Let default newline behavior happen
                }
                sendMessage()
                return .handled
            }

        Button {
            if conversation.isStreaming {
                conversation.stopStreaming()
            } else {
                sendMessage()
            }
        } label: {
            Image(systemName: conversation.isStreaming ? "stop.circle.fill" : "arrow.up.circle.fill")
                .font(.system(size: 24))
                .foregroundStyle(conversation.isStreaming ? .red : .accentColor)
        }
        .buttonStyle(.plain)
        .disabled(!conversation.isStreaming && inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 10)
    .background {
        RoundedRectangle(cornerRadius: 12)
            .fill(.ultraThinMaterial)
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.quaternary, lineWidth: 0.5)
            }
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 8)
}
```

- [ ] **Step 4: Add regenerate notification handler**

In the ChatPanelView body, add:

```swift
.onReceive(NotificationCenter.default.publisher(for: .regenerateLastResponse)) { _ in
    Task {
        await conversation.regenerateLastResponse()
    }
}
```

- [ ] **Step 5: Remove the old `attributedMarkdown` helper** (now handled by MarkdownContentView)

- [ ] **Step 6: Build to verify**

Run: `xcodebuild build -scheme Teleprompter -destination 'platform=macOS' 2>&1 | tail -20`
Expected: BUILD SUCCEEDED

- [ ] **Step 7: Commit**

```bash
git add Teleprompter/Views/ScriptAssistant/ChatPanelView.swift
git commit -m "Redesign chat panel with flat layout, stop button, and improved input"
```

---

## Chunk 4: Scroll-to-Bottom & Preview Enhancements

### Task 10: Add scroll-to-bottom button to ChatPanelView

**Files:**
- Modify: `Teleprompter/Views/ScriptAssistant/ChatPanelView.swift`

- [ ] **Step 1: Add scroll position tracking state**

Add to ChatPanelView:

```swift
@State private var isAtBottom = true
@State private var hasNewContent = false
```

- [ ] **Step 2: Add the floating scroll-to-bottom button as an overlay**

Wrap the ScrollView in a ZStack and add the button:

```swift
ZStack(alignment: .bottomTrailing) {
    ScrollViewReader { proxy in
        ScrollView {
            // ... existing LazyVStack content ...
        }
        // ... existing onChange handlers ...
        .onChange(of: conversation.messages.count) {
            if isAtBottom {
                withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
            } else {
                hasNewContent = true
            }
        }
        .onChange(of: conversation.currentStreamingText) {
            if conversation.isStreaming && isAtBottom {
                proxy.scrollTo("bottom", anchor: .bottom)
            }
        }
    }

    // Scroll-to-bottom button
    if !isAtBottom {
        Button {
            isAtBottom = true
            hasNewContent = false
            // scrollTo will be triggered by isAtBottom change
        } label: {
            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                    .frame(width: 32, height: 32)
                    .shadow(color: .black.opacity(0.1), radius: 4, y: 2)

                Image(systemName: "chevron.down")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)

                // New content badge
                if hasNewContent {
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 8, height: 8)
                        .offset(x: 10, y: -10)
                }
            }
        }
        .buttonStyle(.plain)
        .padding(.trailing, 16)
        .padding(.bottom, 16)
        .transition(.opacity.combined(with: .scale))
    }
}
```

To detect scroll position, add a `GeometryReader` inside the scroll content anchored to the bottom. When the bottom anchor is visible in the scroll view's coordinate space, the user is at the bottom:

```swift
// Add this inside the LazyVStack, after the Color.clear anchor:
GeometryReader { geo in
    Color.clear
        .preference(key: ScrollOffsetPreferenceKey.self,
                     value: geo.frame(in: .named("chatScroll")).maxY)
}
.frame(height: 0)
```

Add the preference key and coordinate space:

```swift
private struct ScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
```

On the ScrollView, add `.coordinateSpace(name: "chatScroll")` and:

```swift
.onPreferenceChange(ScrollOffsetPreferenceKey.self) { maxY in
    // If bottom of content is within 100pt of the scroll view bottom, we're "at bottom"
    // Compare against the scroll view's visible height
    isAtBottom = maxY < 100
}
```

Alternatively, if targeting macOS 14+, use `.onScrollGeometryChange(for:)` which is cleaner.

- [ ] **Step 3: Build to verify**

Run: `xcodebuild build -scheme Teleprompter -destination 'platform=macOS' 2>&1 | tail -20`
Expected: BUILD SUCCEEDED

- [ ] **Step 4: Commit**

```bash
git add Teleprompter/Views/ScriptAssistant/ChatPanelView.swift
git commit -m "Add floating scroll-to-bottom button with new content badge"
```

### Task 11: Enhance ScriptPreviewPanel with active slide indicator

**Files:**
- Modify: `Teleprompter/Views/ScriptAssistant/ScriptPreviewPanel.swift`
- Modify: `Teleprompter/Views/ScriptAssistant/ScriptAssistantView.swift`

- [ ] **Step 1: Pass activelyStreamingSlideNumber to ScriptPreviewPanel**

In `ScriptAssistantView.swift`, update the ScriptPreviewPanel instantiation to accept the conversation's active slide number:

```swift
ScriptPreviewPanel(
    script: script,
    totalSlides: slides.count,
    targetDurationMinutes: targetMinutes,
    activeSlideNumber: conversation?.activelyStreamingSlideNumber
)
```

- [ ] **Step 2: Add pulsing border to active slide in ScriptPreviewPanel**

In `ScriptPreviewPanel.swift`, add the parameter:

```swift
let activeSlideNumber: Int?
```

Update `previewSection` to show a pulsing border when active:

```swift
private func previewSection(_ section: ScriptSection) -> some View {
    let isActive = activeSlideNumber == section.slideNumber

    return VStack(alignment: .leading, spacing: 6) {
        // ... existing content ...
    }
    .overlay {
        if isActive {
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.accentColor, lineWidth: 2)
                .opacity(pulsingOpacity)
                .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: pulsingOpacity)
        }
    }
}
```

Add `@State private var pulsingOpacity: Double = 0.3` and toggle it via `.onAppear`.

- [ ] **Step 3: Add auto-scroll to active slide in preview**

Wrap the preview ScrollView with ScrollViewReader. Give each previewSection an `.id(section.slideNumber)`. When `activeSlideNumber` changes, scroll to that slide:

```swift
.onChange(of: activeSlideNumber) { _, newValue in
    if let slideNum = newValue {
        withAnimation {
            proxy.scrollTo(slideNum, anchor: .center)
        }
    }
}
```

- [ ] **Step 4: Build to verify**

Run: `xcodebuild build -scheme Teleprompter -destination 'platform=macOS' 2>&1 | tail -20`
Expected: BUILD SUCCEEDED

- [ ] **Step 5: Run all tests**

Run: `xcodebuild test -scheme Teleprompter -destination 'platform=macOS' 2>&1 | tail -30`
Expected: All pass.

- [ ] **Step 6: Commit**

```bash
git add Teleprompter/Views/ScriptAssistant/ScriptPreviewPanel.swift Teleprompter/Views/ScriptAssistant/ScriptAssistantView.swift
git commit -m "Add pulsing indicator and auto-scroll for active slide in preview"
```

---

## Chunk 5: Process Cancellation & Final Integration

### Task 12: Add Process cancellation to ClaudeCLIProvider

**Files:**
- Modify: `Teleprompter/LLM/ClaudeCLIProvider.swift`

- [ ] **Step 1: Store Process reference and add onTermination handler**

Update the `stream` method to store the process and handle cancellation:

```swift
func stream(messages: [ChatMessage]) async throws -> AsyncStream<String> {
    let prompt = Self.formatPrompt(messages: messages)

    guard let claudePath = Self.resolvedClaudePath() else {
        return AsyncStream { continuation in
            continuation.yield("[Error: Claude CLI not found]")
            continuation.finish()
        }
    }

    return AsyncStream { continuation in
        let process = Process()
        process.executableURL = URL(fileURLWithPath: claudePath)
        process.arguments = self.buildArguments()

        let inputPipe = Pipe()
        let outputPipe = Pipe()
        let errorPipe = Pipe()

        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        continuation.onTermination = { _ in
            if process.isRunning {
                process.terminate()
            }
        }

        Task.detached {
            do {
                try process.run()

                let promptData = prompt.data(using: .utf8) ?? Data()
                inputPipe.fileHandleForWriting.write(promptData)
                inputPipe.fileHandleForWriting.closeFile()

                let handle = outputPipe.fileHandleForReading
                var data = handle.readData(ofLength: 4096)
                while !data.isEmpty {
                    if let chunk = String(data: data, encoding: .utf8) {
                        continuation.yield(chunk)
                    }
                    data = handle.readData(ofLength: 4096)
                }

                process.waitUntilExit()

                if process.terminationStatus != 0 && process.terminationStatus != 15 {
                    // 15 = SIGTERM from our cancellation, which is expected
                    let errData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                    let errMsg = String(data: errData, encoding: .utf8) ?? "Unknown error"
                    continuation.yield("\n\n[Error: Claude CLI exited with code \(process.terminationStatus): \(errMsg)]")
                }

                continuation.finish()
            } catch {
                continuation.yield("\n\n[Error: \(error.localizedDescription)]")
                continuation.finish()
            }
        }
    }
}
```

The key change is `continuation.onTermination` which terminates the process when the `AsyncStream` consumer cancels. Also, termination status 15 (SIGTERM) is now expected and not treated as an error.

- [ ] **Step 2: Build and run tests**

Run: `xcodebuild test -scheme Teleprompter -destination 'platform=macOS' 2>&1 | tail -30`
Expected: All pass.

- [ ] **Step 3: Commit**

```bash
git add Teleprompter/LLM/ClaudeCLIProvider.swift
git commit -m "Add process cancellation support to ClaudeCLIProvider"
```

### Task 13: Remove context bar from ChatPanelView

**Files:**
- Modify: `Teleprompter/Views/ScriptAssistant/ChatPanelView.swift`

- [ ] **Step 1: Remove the context bar**

The context bar at the top of ChatPanelView (showing slide count and provider name) duplicates information now available in the top bar. Remove the entire block:

```swift
// Remove this block:
HStack(spacing: 8) {
    Text("\(conversation.slideCount) slides loaded")
    // ...
}
.padding(.horizontal, 16)
.padding(.vertical, 8)
.background(.ultraThinMaterial)

Divider()
```

This reclaims ~30pt of vertical space for message content.

- [ ] **Step 2: Build to verify**

Run: `xcodebuild build -scheme Teleprompter -destination 'platform=macOS' 2>&1 | tail -20`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add Teleprompter/Views/ScriptAssistant/ChatPanelView.swift
git commit -m "Remove redundant context bar from chat panel"
```

### Task 14: Final integration test and cleanup

**Files:**
- All modified files

- [ ] **Step 1: Run full test suite**

Run: `xcodebuild test -scheme Teleprompter -destination 'platform=macOS' 2>&1 | tail -30`
Expected: All tests pass.

- [ ] **Step 2: Build and verify the app launches**

Run: `xcodebuild build -scheme Teleprompter -destination 'platform=macOS' 2>&1 | tail -20`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Verify no warnings in modified files**

Run: `xcodebuild build -scheme Teleprompter -destination 'platform=macOS' 2>&1 | grep -i warning | head -20`
Expected: No warnings in the files we modified.

- [ ] **Step 4: Final commit if any cleanup was needed**

```bash
git add -A
git commit -m "Final cleanup for assistant window UX redesign"
```
