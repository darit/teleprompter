# Teleprompter Plan 2: PPTX Parsing, LLM Provider & Script Assistant

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Enable importing PPTX files, chatting with an LLM to generate speech scripts, and previewing the result -- the core content creation flow.

**Architecture:** PPTX files are parsed via Foundation ZIP + XMLParser into `SlideContent` structs. An `LLMProvider` protocol abstracts LLM access; the initial implementation uses the Claude Code CLI (`claude -p`). A `ScriptAssistantView` presents a split-view chat + script preview. A `ConversationManager` orchestrates the multi-turn conversation, maintains message history, and parses LLM responses to update script sections.

**Tech Stack:** Swift 6.2, SwiftUI, SwiftData, Foundation (ZIP/XML), Process (CLI invocation)

**Spec:** `docs/superpowers/specs/2026-03-12-teleprompter-design.md`

**Depends on:** Plan 1 (Foundation) -- completed

**Deferred to later plans:**
- MLX local inference provider (needs SPM dependencies)
- Model download from HuggingFace
- Copilot CLI provider
- Local API provider (LM Studio/Ollama)
- Remote API providers (Claude API, OpenAI API)
- Settings view

---

## File Structure

```
Teleprompter/
  Teleprompter/
    PPTX/
      SlideContent.swift              # Data types for extracted slide content
      PPTXParser.swift                # ZIP decompression + XML parsing
    LLM/
      ChatMessage.swift               # Message type (role + content)
      LLMProvider.swift               # Protocol for LLM providers
      ClaudeCLIProvider.swift         # Claude Code CLI subprocess provider
    Services/
      ConversationManager.swift       # Manages chat history, sends to LLM, parses responses
      PromptTemplates.swift           # System prompt and response format instructions
    Views/
      ScriptAssistant/
        ScriptAssistantView.swift     # Main split view (chat + preview)
        ChatPanelView.swift           # Left panel: messages + input
        ChatMessageView.swift         # Single chat message bubble
        ScriptPreviewPanel.swift      # Right panel: live script preview
    Views/ScriptManager/
      ScriptSidebarView.swift         # MODIFY: wire Import button
      ScriptDetailView.swift          # MODIFY: wire Refine with AI button
      ScriptManagerView.swift         # MODIFY: add navigation to assistant
  TeleprompterTests/
    PPTX/
      PPTXParserTests.swift           # PPTX parsing tests
    LLM/
      ChatMessageTests.swift          # ChatMessage tests
      ClaudeCLIProviderTests.swift    # CLI provider tests (mocked process)
    Services/
      ConversationManagerTests.swift  # Conversation flow tests
```

---

## Chunk 1: PPTX Parsing and LLM Provider

### Task 1: SlideContent Data Types

**Files:**
- Create: `Teleprompter/Teleprompter/PPTX/SlideContent.swift`

- [ ] **Step 1: Create SlideContent types**

```swift
// Teleprompter/PPTX/SlideContent.swift
import Foundation

struct SlideContent: Identifiable, Sendable {
    let id = UUID()
    let slideNumber: Int
    let title: String
    let bodyText: String
    let notes: String

    var isEmpty: Bool {
        title.isEmpty && bodyText.isEmpty
    }

    var summary: String {
        if !title.isEmpty {
            return "Slide \(slideNumber): \(title)"
        }
        let preview = String(bodyText.prefix(60))
        return "Slide \(slideNumber): \(preview)..."
    }
}

struct PPTXParseResult: Sendable {
    let fileName: String
    let slides: [SlideContent]
    let warnings: [String]
}

enum PPTXParseError: LocalizedError {
    case invalidFile(String)
    case encrypted
    case noSlidesFound

    var errorDescription: String? {
        switch self {
        case .invalidFile(let detail): return "This file could not be read as a PowerPoint presentation: \(detail)"
        case .encrypted: return "This file is password-protected and cannot be imported."
        case .noSlidesFound: return "No slides were found in this presentation."
        }
    }
}
```

- [ ] **Step 2: Build to verify**

Run: `xcodebuild build -scheme Teleprompter -destination 'platform=macOS'`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add Teleprompter/Teleprompter/PPTX/SlideContent.swift
git commit -m "Add SlideContent data types for PPTX parsing"
```

---

### Task 2: PPTX Parser

**Files:**
- Create: `Teleprompter/Teleprompter/PPTX/PPTXParser.swift`
- Create: `Teleprompter/TeleprompterTests/PPTX/PPTXParserTests.swift`

- [ ] **Step 1: Write tests for PPTXParser**

```swift
// TeleprompterTests/PPTX/PPTXParserTests.swift
import Testing
import Foundation
@testable import Teleprompter

@Suite("PPTX Parser")
struct PPTXParserTests {

    @Test("rejects non-ZIP file")
    func testRejectsNonZip() async throws {
        let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent("fake.pptx")
        try "not a zip file".data(using: .utf8)!.write(to: tempFile)
        defer { try? FileManager.default.removeItem(at: tempFile) }

        do {
            _ = try PPTXParser.parse(fileAt: tempFile)
            Issue.record("Expected PPTXParseError.invalidFile")
        } catch is PPTXParseError {
            // expected
        }
    }

    @Test("extracts text from slide XML")
    func testExtractTextFromSlideXML() {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <p:sld xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main"
               xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main"
               xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
          <p:cSld>
            <p:spTree>
              <p:sp>
                <p:nvSpPr><p:nvPr><p:ph type="title"/></p:nvPr></p:nvSpPr>
                <p:txBody>
                  <a:p><a:r><a:t>My Title</a:t></a:r></a:p>
                </p:txBody>
              </p:sp>
              <p:sp>
                <p:nvSpPr><p:nvPr><p:ph type="body"/></p:nvPr></p:nvSpPr>
                <p:txBody>
                  <a:p><a:r><a:t>Bullet one</a:t></a:r></a:p>
                  <a:p><a:r><a:t>Bullet two</a:t></a:r></a:p>
                </p:txBody>
              </p:sp>
            </p:spTree>
          </p:cSld>
        </p:sld>
        """
        let data = xml.data(using: .utf8)!
        let result = PPTXParser.extractSlideContent(from: data, slideNumber: 1)

        #expect(result.title == "My Title")
        #expect(result.bodyText.contains("Bullet one"))
        #expect(result.bodyText.contains("Bullet two"))
    }

    @Test("extracts notes from notes XML")
    func testExtractNotes() {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <p:notes xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main"
                 xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main">
          <p:cSld>
            <p:spTree>
              <p:sp>
                <p:nvSpPr><p:nvPr><p:ph type="body" idx="1"/></p:nvPr></p:nvSpPr>
                <p:txBody>
                  <a:p><a:r><a:t>Speaker notes here</a:t></a:r></a:p>
                </p:txBody>
              </p:sp>
            </p:spTree>
          </p:cSld>
        </p:notes>
        """
        let data = xml.data(using: .utf8)!
        let notes = PPTXParser.extractNotes(from: data)

        #expect(notes == "Speaker notes here")
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -scheme Teleprompter -destination 'platform=macOS'`
Expected: FAIL -- `PPTXParser` not defined

- [ ] **Step 3: Implement PPTXParser**

```swift
// Teleprompter/PPTX/PPTXParser.swift
import Foundation

enum PPTXParser {

    /// Parse a PPTX file and extract slide content.
    static func parse(fileAt url: URL) throws -> PPTXParseResult {
        let fileManager = FileManager.default
        let tempDir = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)

        defer { try? fileManager.removeItem(at: tempDir) }

        // PPTX is a ZIP archive -- unzip it
        do {
            try fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true)
            try fileManager.unzipItem(at: url, to: tempDir)
        } catch {
            throw PPTXParseError.invalidFile("Could not decompress file: \(error.localizedDescription)")
        }

        // Check for encryption marker
        let encryptionFile = tempDir.appendingPathComponent("EncryptedPackage")
        if fileManager.fileExists(atPath: encryptionFile.path) {
            throw PPTXParseError.encrypted
        }

        // Read presentation.xml for slide ordering
        let presentationURL = tempDir.appendingPathComponent("ppt/presentation.xml")
        guard let presentationData = try? Data(contentsOf: presentationURL) else {
            throw PPTXParseError.invalidFile("Missing ppt/presentation.xml")
        }

        let slideIds = extractSlideRelationshipIds(from: presentationData)

        // Read relationships to map rIds to slide file paths
        let relsURL = tempDir.appendingPathComponent("ppt/_rels/presentation.xml.rels")
        guard let relsData = try? Data(contentsOf: relsURL) else {
            throw PPTXParseError.invalidFile("Missing presentation relationships")
        }
        let rIdToFile = extractRelationships(from: relsData)

        var slides: [SlideContent] = []
        var warnings: [String] = []

        for (index, rId) in slideIds.enumerated() {
            let slideNumber = index + 1
            guard let slideFile = rIdToFile[rId] else {
                warnings.append("Slide \(slideNumber): could not resolve relationship \(rId)")
                continue
            }

            let slidePath = "ppt/\(slideFile)"
            let slideURL = tempDir.appendingPathComponent(slidePath)

            guard let slideData = try? Data(contentsOf: slideURL) else {
                warnings.append("Slide \(slideNumber): could not read \(slidePath)")
                continue
            }

            var slide = extractSlideContent(from: slideData, slideNumber: slideNumber)

            // Try to read notes
            let noteFile = slideFile.replacingOccurrences(of: "slides/slide", with: "notesSlides/notesSlide")
            let notePath = "ppt/\(noteFile)"
            let noteURL = tempDir.appendingPathComponent(notePath)
            if let noteData = try? Data(contentsOf: noteURL) {
                let notes = extractNotes(from: noteData)
                slide = SlideContent(slideNumber: slide.slideNumber, title: slide.title, bodyText: slide.bodyText, notes: notes)
            }

            slides.append(slide)
        }

        if slides.isEmpty {
            throw PPTXParseError.noSlidesFound
        }

        let fileName = url.deletingPathExtension().lastPathComponent
        return PPTXParseResult(fileName: fileName, slides: slides, warnings: warnings)
    }

    // MARK: - XML Extraction (internal for testing)

    /// Extract text content from a slide XML.
    static func extractSlideContent(from data: Data, slideNumber: Int) -> SlideContent {
        let parser = SlideXMLParser(data: data)
        parser.parse()
        return SlideContent(
            slideNumber: slideNumber,
            title: parser.titleText.joined(separator: " "),
            bodyText: parser.bodyParagraphs.joined(separator: "\n"),
            notes: ""
        )
    }

    /// Extract notes text from a notes slide XML.
    static func extractNotes(from data: Data) -> String {
        let parser = NotesXMLParser(data: data)
        parser.parse()
        return parser.notesParagraphs.joined(separator: "\n")
    }

    /// Extract ordered slide relationship IDs from presentation.xml.
    private static func extractSlideRelationshipIds(from data: Data) -> [String] {
        let parser = PresentationXMLParser(data: data)
        parser.parse()
        return parser.slideRelationshipIds
    }

    /// Extract relationship ID to target file mapping from .rels XML.
    private static func extractRelationships(from data: Data) -> [String: String] {
        let parser = RelsXMLParser(data: data)
        parser.parse()
        return parser.relationships
    }
}

// MARK: - Slide XML Parser

private class SlideXMLParser: NSObject, XMLParserDelegate {
    private let xmlParser: XMLParser
    var titleText: [String] = []
    var bodyParagraphs: [String] = []

    private var currentText = ""
    private var isInTitleShape = false
    private var isInBodyShape = false
    private var isCollectingText = false
    private var currentParagraphTexts: [String] = []
    private var placeholderType: String?

    init(data: Data) {
        self.xmlParser = XMLParser(data: data)
        super.init()
        xmlParser.delegate = self
    }

    func parse() {
        xmlParser.parse()
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?,
                attributes attributeDict: [String: String] = [:]) {
        let localName = elementName.components(separatedBy: ":").last ?? elementName

        if localName == "ph" {
            placeholderType = attributeDict["type"]
        }

        if localName == "txBody" {
            if placeholderType == "title" || placeholderType == "ctrTitle" {
                isInTitleShape = true
            } else {
                isInBodyShape = true
            }
        }

        if localName == "p" && (isInTitleShape || isInBodyShape) {
            currentParagraphTexts = []
        }

        if localName == "t" {
            isCollectingText = true
            currentText = ""
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if isCollectingText {
            currentText += string
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?) {
        let localName = elementName.components(separatedBy: ":").last ?? elementName

        if localName == "t" {
            isCollectingText = false
            if isInTitleShape || isInBodyShape {
                currentParagraphTexts.append(currentText)
            }
        }

        if localName == "p" {
            let paragraphText = currentParagraphTexts.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
            if !paragraphText.isEmpty {
                if isInTitleShape {
                    titleText.append(paragraphText)
                } else if isInBodyShape {
                    bodyParagraphs.append(paragraphText)
                }
            }
            currentParagraphTexts = []
        }

        if localName == "txBody" {
            isInTitleShape = false
            isInBodyShape = false
        }

        if localName == "sp" {
            placeholderType = nil
        }
    }
}

// MARK: - Notes XML Parser

private class NotesXMLParser: NSObject, XMLParserDelegate {
    private let xmlParser: XMLParser
    var notesParagraphs: [String] = []

    private var isInNotesBody = false
    private var isCollectingText = false
    private var currentText = ""
    private var currentParagraphTexts: [String] = []
    private var placeholderType: String?
    private var placeholderIdx: String?

    init(data: Data) {
        self.xmlParser = XMLParser(data: data)
        super.init()
        xmlParser.delegate = self
    }

    func parse() {
        xmlParser.parse()
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?,
                attributes attributeDict: [String: String] = [:]) {
        let localName = elementName.components(separatedBy: ":").last ?? elementName

        if localName == "ph" {
            placeholderType = attributeDict["type"]
            placeholderIdx = attributeDict["idx"]
        }

        if localName == "txBody" {
            // Notes body is type="body" with idx="1"
            if placeholderType == "body" && placeholderIdx == "1" {
                isInNotesBody = true
            }
        }

        if localName == "p" && isInNotesBody {
            currentParagraphTexts = []
        }

        if localName == "t" {
            isCollectingText = true
            currentText = ""
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if isCollectingText {
            currentText += string
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?) {
        let localName = elementName.components(separatedBy: ":").last ?? elementName

        if localName == "t" {
            isCollectingText = false
            if isInNotesBody {
                currentParagraphTexts.append(currentText)
            }
        }

        if localName == "p" && isInNotesBody {
            let text = currentParagraphTexts.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                notesParagraphs.append(text)
            }
            currentParagraphTexts = []
        }

        if localName == "txBody" {
            isInNotesBody = false
        }

        if localName == "sp" {
            placeholderType = nil
            placeholderIdx = nil
        }
    }
}

// MARK: - Presentation XML Parser

private class PresentationXMLParser: NSObject, XMLParserDelegate {
    private let xmlParser: XMLParser
    var slideRelationshipIds: [String] = []

    init(data: Data) {
        self.xmlParser = XMLParser(data: data)
        super.init()
        xmlParser.delegate = self
    }

    func parse() {
        xmlParser.parse()
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?,
                attributes attributeDict: [String: String] = [:]) {
        let localName = elementName.components(separatedBy: ":").last ?? elementName

        if localName == "sldId", let rId = attributeDict["r:id"] {
            slideRelationshipIds.append(rId)
        }
    }
}

// MARK: - Relationships XML Parser

private class RelsXMLParser: NSObject, XMLParserDelegate {
    private let xmlParser: XMLParser
    var relationships: [String: String] = [:]

    init(data: Data) {
        self.xmlParser = XMLParser(data: data)
        super.init()
        xmlParser.delegate = self
    }

    func parse() {
        xmlParser.parse()
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?,
                attributes attributeDict: [String: String] = [:]) {
        if elementName == "Relationship",
           let id = attributeDict["Id"],
           let target = attributeDict["Target"] {
            relationships[id] = target
        }
    }
}

// MARK: - FileManager ZIP Extension

extension FileManager {
    /// Unzip a file to a destination directory using the `unzip` command.
    func unzipItem(at sourceURL: URL, to destinationURL: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-o", "-q", sourceURL.path, "-d", destinationURL.path]

        let errorPipe = Pipe()
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let errorMessage = String(data: errorData, encoding: .utf8) ?? "Unknown error"
            throw PPTXParseError.invalidFile("ZIP extraction failed: \(errorMessage)")
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -scheme Teleprompter -destination 'platform=macOS'`
Expected: ALL PASS

- [ ] **Step 5: Commit**

```bash
git add Teleprompter/Teleprompter/PPTX/PPTXParser.swift Teleprompter/TeleprompterTests/PPTX/PPTXParserTests.swift
git commit -m "Add PPTX parser with ZIP extraction and XML text parsing"
```

---

### Task 3: ChatMessage and LLMProvider Protocol

**Files:**
- Create: `Teleprompter/Teleprompter/LLM/ChatMessage.swift`
- Create: `Teleprompter/Teleprompter/LLM/LLMProvider.swift`
- Create: `Teleprompter/TeleprompterTests/LLM/ChatMessageTests.swift`

- [ ] **Step 1: Write ChatMessage tests**

```swift
// TeleprompterTests/LLM/ChatMessageTests.swift
import Testing
import Foundation
@testable import Teleprompter

@Suite("ChatMessage")
struct ChatMessageTests {

    @Test("creates system message")
    func testSystemMessage() {
        let msg = ChatMessage(role: .system, content: "You are a coach.")
        #expect(msg.role == .system)
        #expect(msg.content == "You are a coach.")
    }

    @Test("creates user message")
    func testUserMessage() {
        let msg = ChatMessage(role: .user, content: "Hello")
        #expect(msg.role == .user)
        #expect(msg.content == "Hello")
    }

    @Test("creates assistant message")
    func testAssistantMessage() {
        let msg = ChatMessage(role: .assistant, content: "Hi there")
        #expect(msg.role == .assistant)
        #expect(msg.content == "Hi there")
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -scheme Teleprompter -destination 'platform=macOS'`
Expected: FAIL -- `ChatMessage` not defined

- [ ] **Step 3: Implement ChatMessage and LLMProvider**

```swift
// Teleprompter/LLM/ChatMessage.swift
import Foundation

struct ChatMessage: Identifiable, Sendable {
    let id = UUID()
    let role: Role
    let content: String
    let timestamp: Date

    enum Role: String, Sendable {
        case system
        case user
        case assistant
    }

    init(role: Role, content: String, timestamp: Date = .now) {
        self.role = role
        self.content = content
        self.timestamp = timestamp
    }
}
```

```swift
// Teleprompter/LLM/LLMProvider.swift
import Foundation

protocol LLMProvider: Sendable {
    /// Stream a response from the LLM given a conversation history.
    func stream(messages: [ChatMessage]) async throws -> AsyncStream<String>

    /// Human-readable name for this provider (e.g. "Claude Code CLI (Sonnet)").
    var displayName: String { get }

    /// Whether this provider is currently available (e.g. CLI found in PATH).
    var isAvailable: Bool { get }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -scheme Teleprompter -destination 'platform=macOS'`
Expected: ALL PASS

- [ ] **Step 5: Commit**

```bash
git add Teleprompter/Teleprompter/LLM/ChatMessage.swift Teleprompter/Teleprompter/LLM/LLMProvider.swift Teleprompter/TeleprompterTests/LLM/ChatMessageTests.swift
git commit -m "Add ChatMessage type and LLMProvider protocol"
```

---

### Task 4: Claude CLI Provider

**Files:**
- Create: `Teleprompter/Teleprompter/LLM/ClaudeCLIProvider.swift`
- Create: `Teleprompter/TeleprompterTests/LLM/ClaudeCLIProviderTests.swift`

- [ ] **Step 1: Write tests**

```swift
// TeleprompterTests/LLM/ClaudeCLIProviderTests.swift
import Testing
import Foundation
@testable import Teleprompter

@Suite("Claude CLI Provider")
struct ClaudeCLIProviderTests {

    @Test("display name includes model")
    func testDisplayName() {
        let provider = ClaudeCLIProvider(model: .sonnet)
        #expect(provider.displayName == "Claude Code CLI (Sonnet)")

        let opusProvider = ClaudeCLIProvider(model: .opus)
        #expect(opusProvider.displayName == "Claude Code CLI (Opus)")
    }

    @Test("builds correct command arguments")
    func testCommandArguments() {
        let provider = ClaudeCLIProvider(model: .sonnet)
        let args = provider.buildArguments()
        #expect(args.contains("-p"))
        #expect(args.contains("--model"))
        #expect(args.contains("sonnet"))
    }

    @Test("formats messages into prompt")
    func testPromptFormatting() {
        let messages: [ChatMessage] = [
            ChatMessage(role: .system, content: "You are a coach."),
            ChatMessage(role: .user, content: "Help me with slide 1"),
            ChatMessage(role: .assistant, content: "Sure, tell me more."),
            ChatMessage(role: .user, content: "It's about architecture."),
        ]
        let prompt = ClaudeCLIProvider.formatPrompt(messages: messages)

        #expect(prompt.contains("You are a coach."))
        #expect(prompt.contains("Help me with slide 1"))
        #expect(prompt.contains("Sure, tell me more."))
        #expect(prompt.contains("It's about architecture."))
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -scheme Teleprompter -destination 'platform=macOS'`
Expected: FAIL -- `ClaudeCLIProvider` not defined

- [ ] **Step 3: Implement ClaudeCLIProvider**

```swift
// Teleprompter/LLM/ClaudeCLIProvider.swift
import Foundation

final class ClaudeCLIProvider: LLMProvider, @unchecked Sendable {

    enum Model: String, Sendable {
        case opus
        case sonnet
    }

    let model: Model
    private let timeoutSeconds: TimeInterval

    init(model: Model = .sonnet, timeoutSeconds: TimeInterval = 300) {
        self.model = model
        self.timeoutSeconds = timeoutSeconds
    }

    var displayName: String {
        "Claude Code CLI (\(model.rawValue.capitalized))"
    }

    var isAvailable: Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = ["claude"]
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    func stream(messages: [ChatMessage]) async throws -> AsyncStream<String> {
        let prompt = Self.formatPrompt(messages: messages)

        return AsyncStream { continuation in
            Task.detached {
                do {
                    let process = Process()
                    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
                    process.arguments = ["claude"] + self.buildArguments()

                    let inputPipe = Pipe()
                    let outputPipe = Pipe()
                    let errorPipe = Pipe()

                    process.standardInput = inputPipe
                    process.standardOutput = outputPipe
                    process.standardError = errorPipe

                    try process.run()

                    // Write prompt to stdin and close
                    let promptData = prompt.data(using: .utf8) ?? Data()
                    inputPipe.fileHandleForWriting.write(promptData)
                    inputPipe.fileHandleForWriting.closeFile()

                    // Read stdout in fixed-size chunks (4096 bytes)
                    let handle = outputPipe.fileHandleForReading
                    var data = handle.readData(ofLength: 4096)
                    while !data.isEmpty {
                        if let chunk = String(data: data, encoding: .utf8) {
                            continuation.yield(chunk)
                        }
                        data = handle.readData(ofLength: 4096)
                    }

                    process.waitUntilExit()

                    if process.terminationStatus != 0 {
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

    // MARK: - Internal (visible for testing)

    func buildArguments() -> [String] {
        ["-p", "--model", model.rawValue]
    }

    static func formatPrompt(messages: [ChatMessage]) -> String {
        var parts: [String] = []

        for message in messages {
            switch message.role {
            case .system:
                parts.append("[System Instructions]\n\(message.content)")
            case .user:
                parts.append("[User]\n\(message.content)")
            case .assistant:
                parts.append("[Assistant]\n\(message.content)")
            }
        }

        return parts.joined(separator: "\n\n---\n\n")
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -scheme Teleprompter -destination 'platform=macOS'`
Expected: ALL PASS

- [ ] **Step 5: Commit**

```bash
git add Teleprompter/Teleprompter/LLM/ClaudeCLIProvider.swift Teleprompter/TeleprompterTests/LLM/ClaudeCLIProviderTests.swift
git commit -m "Add Claude Code CLI provider with streaming output"
```

---

## Chunk 2: Conversation Engine

### Task 5: Prompt Templates

**Files:**
- Create: `Teleprompter/Teleprompter/Services/PromptTemplates.swift`

- [ ] **Step 1: Create prompt templates**

```swift
// Teleprompter/Services/PromptTemplates.swift
import Foundation

enum PromptTemplates {

    static func systemPrompt(slides: [SlideContent], targetDurationMinutes: Int?) -> String {
        var prompt = """
        You are a presentation coach helping prepare a speech script. The presenter will deliver this talk live via video call.

        SLIDE CONTENT:
        """

        for slide in slides {
            prompt += "\n\n--- Slide \(slide.slideNumber): \(slide.title) ---"
            if !slide.bodyText.isEmpty {
                prompt += "\n\(slide.bodyText)"
            }
            if !slide.notes.isEmpty {
                prompt += "\nSpeaker notes: \(slide.notes)"
            }
        }

        if let duration = targetDurationMinutes {
            prompt += """

            \n\nTARGET DURATION: ~\(duration) minutes total.
            Budget time across slides proportionally to their content density. Flag if the running total trends over or under target.
            """
        }

        prompt += """

        \n\nINSTRUCTIONS:
        1. Ask the presenter questions ONE SLIDE AT A TIME to gather additional context (anecdotes, metrics, team members to mention).
        2. After each answer, generate natural speech text for that slide -- conversational, not bullet points.
        3. Reference specific slides by number and quote relevant content.
        4. Suggest mentioning concrete numbers, team members, and real examples.
        5. After generating text for a slide, move to the next one.

        RESPONSE FORMAT:
        When generating script text for a slide, wrap it in markers:
        [SCRIPT_START slide=N]
        The actual speech text here...
        [SCRIPT_END]

        When asking a question (not generating script), just write the question normally without markers.

        Start by briefly summarizing what you see across all slides, then ask about the first slide.
        """

        return prompt
    }
}
```

- [ ] **Step 2: Build to verify**

Run: `xcodebuild build -scheme Teleprompter -destination 'platform=macOS'`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add Teleprompter/Teleprompter/Services/PromptTemplates.swift
git commit -m "Add prompt templates for script generation"
```

---

### Task 6: ConversationManager

**Files:**
- Create: `Teleprompter/Teleprompter/Services/ConversationManager.swift`
- Create: `Teleprompter/TeleprompterTests/Services/ConversationManagerTests.swift`

- [ ] **Step 1: Write tests**

```swift
// TeleprompterTests/Services/ConversationManagerTests.swift
import Testing
import Foundation
@testable import Teleprompter

@Suite("ConversationManager")
struct ConversationManagerTests {

    @Test("parses script markers from response")
    func testParseScriptMarkers() {
        let text = """
        Here's the script for slide 1:

        [SCRIPT_START slide=1]
        Good afternoon everyone. Today we'll review the architecture changes from Q1.
        [SCRIPT_END]

        Now, for slide 2, can you tell me more about the performance improvements?
        """

        let segments = ConversationManager.parseResponse(text)

        #expect(segments.count == 3)
        #expect(segments[0].type == .text)
        #expect(segments[1].type == .script(slideNumber: 1))
        #expect(segments[1].content.contains("Good afternoon"))
        #expect(segments[2].type == .text)
        #expect(segments[2].content.contains("slide 2"))
    }

    @Test("handles response with no script markers")
    func testNoMarkers() {
        let text = "Can you tell me more about your team structure?"
        let segments = ConversationManager.parseResponse(text)

        #expect(segments.count == 1)
        #expect(segments[0].type == .text)
        #expect(segments[0].content.contains("team structure"))
    }

    @Test("handles multiple script blocks")
    func testMultipleBlocks() {
        let text = """
        [SCRIPT_START slide=2]
        Script for slide two.
        [SCRIPT_END]

        [SCRIPT_START slide=3]
        Script for slide three.
        [SCRIPT_END]
        """

        let segments = ConversationManager.parseResponse(text)
        let scriptSegments = segments.filter {
            if case .script = $0.type { return true }
            return false
        }

        #expect(scriptSegments.count == 2)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild test -scheme Teleprompter -destination 'platform=macOS'`
Expected: FAIL -- `ConversationManager` not defined

- [ ] **Step 3: Implement ConversationManager**

```swift
// Teleprompter/Services/ConversationManager.swift
import Foundation
import SwiftData

@Observable
final class ConversationManager {
    var messages: [ChatMessage] = []
    var isStreaming = false
    var currentStreamingText = ""
    var error: String?

    private let provider: any LLMProvider
    private let slides: [SlideContent]
    private let script: Script
    private let targetDurationMinutes: Int?
    private let modelContext: ModelContext

    init(provider: any LLMProvider, slides: [SlideContent], script: Script,
         targetDurationMinutes: Int? = nil, modelContext: ModelContext) {
        self.provider = provider
        self.slides = slides
        self.script = script
        self.targetDurationMinutes = targetDurationMinutes
        self.modelContext = modelContext

        // Add system prompt
        let systemPrompt = PromptTemplates.systemPrompt(
            slides: slides,
            targetDurationMinutes: targetDurationMinutes
        )
        messages.append(ChatMessage(role: .system, content: systemPrompt))
    }

    /// Send a user message and stream the response.
    @MainActor
    func send(_ userMessage: String) async {
        messages.append(ChatMessage(role: .user, content: userMessage))
        await streamResponse()
    }

    /// Start the conversation (sends initial prompt to get LLM's opening message).
    @MainActor
    func start() async {
        await streamResponse()
    }

    @MainActor
    private func streamResponse() async {
        isStreaming = true
        currentStreamingText = ""
        error = nil

        do {
            let stream = try await provider.stream(messages: messages)

            for await chunk in stream {
                currentStreamingText += chunk
            }

            let response = currentStreamingText.trimmingCharacters(in: .whitespacesAndNewlines)
            messages.append(ChatMessage(role: .assistant, content: response))

            // Parse response for script markers and update sections
            let segments = Self.parseResponse(response)
            for segment in segments {
                if case .script(let slideNumber) = segment.type {
                    updateScriptSection(slideNumber: slideNumber, content: segment.content)
                }
            }

            currentStreamingText = ""
        } catch {
            self.error = error.localizedDescription
        }

        isStreaming = false
    }

    private func updateScriptSection(slideNumber: Int, content: String) {
        if let existing = script.sections.first(where: { $0.slideNumber == slideNumber }) {
            existing.content = content
            existing.isAIRefined = true
        } else {
            // Find matching slide for label
            let slide = slides.first { $0.slideNumber == slideNumber }
            let accentColors = ["#4A9EFF", "#34C759", "#FF9500", "#FF2D55", "#AF52DE", "#5AC8FA", "#FFCC00", "#FF6B35"]
            let colorIndex = (slideNumber - 1) % accentColors.count

            let section = ScriptSection(
                slideNumber: slideNumber,
                label: slide?.title ?? "Slide \(slideNumber)",
                content: content,
                order: slideNumber - 1,
                accentColorHex: accentColors[colorIndex],
                isAIRefined: true
            )
            script.sections.append(section)
        }
        script.modifiedAt = .now
    }

    // MARK: - Response Parsing (internal for testing)

    enum SegmentType: Equatable {
        case text
        case script(slideNumber: Int)
    }

    struct ResponseSegment {
        let type: SegmentType
        let content: String
    }

    static func parseResponse(_ text: String) -> [ResponseSegment] {
        var segments: [ResponseSegment] = []
        var remaining = text

        let startPattern = /\[SCRIPT_START\s+slide=(\d+)\]/
        let endMarker = "[SCRIPT_END]"

        while !remaining.isEmpty {
            if let match = remaining.firstMatch(of: startPattern) {
                // Text before the marker
                let before = String(remaining[remaining.startIndex..<match.range.lowerBound])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !before.isEmpty {
                    segments.append(ResponseSegment(type: .text, content: before))
                }

                let slideNumber = Int(match.1)!
                let afterStart = String(remaining[match.range.upperBound...])

                if let endRange = afterStart.range(of: endMarker) {
                    let scriptContent = String(afterStart[afterStart.startIndex..<endRange.lowerBound])
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    segments.append(ResponseSegment(type: .script(slideNumber: slideNumber), content: scriptContent))
                    remaining = String(afterStart[endRange.upperBound...])
                } else {
                    // No end marker found -- treat rest as script
                    let scriptContent = afterStart.trimmingCharacters(in: .whitespacesAndNewlines)
                    segments.append(ResponseSegment(type: .script(slideNumber: slideNumber), content: scriptContent))
                    remaining = ""
                }
            } else {
                // No more markers
                let text = remaining.trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty {
                    segments.append(ResponseSegment(type: .text, content: text))
                }
                remaining = ""
            }
        }

        return segments
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -scheme Teleprompter -destination 'platform=macOS'`
Expected: ALL PASS

- [ ] **Step 5: Commit**

```bash
git add Teleprompter/Teleprompter/Services/ConversationManager.swift Teleprompter/TeleprompterTests/Services/ConversationManagerTests.swift
git commit -m "Add ConversationManager with response parsing and script updates"
```

---

## Chunk 3: Script Assistant Views and Wiring

### Task 7: ChatMessageView Component

**Files:**
- Create: `Teleprompter/Teleprompter/Views/ScriptAssistant/ChatMessageView.swift`

- [ ] **Step 1: Implement chat message bubble**

```swift
// Teleprompter/Views/ScriptAssistant/ChatMessageView.swift
import SwiftUI

struct ChatMessageView: View {
    let message: ChatMessage

    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 60) }

            Text(message.content)
                .font(.system(size: 13))
                .lineSpacing(4)
                .padding(12)
                .background {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(message.role == .user
                              ? Color.accentColor.opacity(0.08)
                              : Color.primary.opacity(0.04))
                }
                .frame(maxWidth: 500, alignment: message.role == .user ? .trailing : .leading)

            if message.role == .assistant { Spacer(minLength: 60) }
        }
    }
}

#Preview("Assistant message") {
    ChatMessageView(message: ChatMessage(role: .assistant, content: "I've reviewed your slides. Let me ask about Slide 1: Introduction. What key points do you want to emphasize?"))
        .padding()
}

#Preview("User message") {
    ChatMessageView(message: ChatMessage(role: .user, content: "I want to mention the team growth from 5 to 12 engineers."))
        .padding()
}
```

- [ ] **Step 2: Build and verify preview renders**

Run: `xcodebuild build -scheme Teleprompter -destination 'platform=macOS'`

- [ ] **Step 3: Commit**

```bash
git add Teleprompter/Teleprompter/Views/ScriptAssistant/ChatMessageView.swift
git commit -m "Add ChatMessageView component"
```

---

### Task 8: ChatPanelView

**Files:**
- Create: `Teleprompter/Teleprompter/Views/ScriptAssistant/ChatPanelView.swift`

- [ ] **Step 1: Implement chat panel**

```swift
// Teleprompter/Views/ScriptAssistant/ChatPanelView.swift
import SwiftUI

struct ChatPanelView: View {
    @Bindable var conversation: ConversationManager
    @State private var inputText = ""
    @FocusState private var isInputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Context bar
            HStack(spacing: 8) {
                Text("\(conversation.slideCount) slides loaded")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)

                Spacer()

                Text(conversation.providerName)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial)

            Divider()

            // Messages
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(conversation.visibleMessages) { message in
                            ChatMessageView(message: message)
                                .id(message.id)
                        }

                        if conversation.isStreaming {
                            HStack {
                                Text(conversation.currentStreamingText.isEmpty
                                     ? "Thinking..."
                                     : conversation.currentStreamingText)
                                    .font(.system(size: 13))
                                    .lineSpacing(4)
                                    .padding(12)
                                    .background {
                                        RoundedRectangle(cornerRadius: 12)
                                            .fill(Color.primary.opacity(0.04))
                                    }
                                    .frame(maxWidth: 500, alignment: .leading)

                                Spacer(minLength: 60)
                            }
                            .id("streaming")
                        }
                    }
                    .padding(16)
                }
                .onChange(of: conversation.messages.count) {
                    withAnimation {
                        proxy.scrollTo(conversation.messages.last?.id, anchor: .bottom)
                    }
                }
                .onChange(of: conversation.currentStreamingText) {
                    if conversation.isStreaming {
                        proxy.scrollTo("streaming", anchor: .bottom)
                    }
                }
            }

            if let error = conversation.error {
                HStack {
                    Image(systemName: "exclamationmark.triangle")
                    Text(error)
                        .font(.system(size: 11))
                }
                .foregroundStyle(.red)
                .padding(8)
            }

            Divider()

            // Input bar
            HStack(spacing: 8) {
                TextField("Type a message...", text: $inputText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...5)
                    .focused($isInputFocused)
                    .onSubmit {
                        sendMessage()
                    }

                Button {
                    sendMessage()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 22))
                }
                .buttonStyle(.plain)
                .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || conversation.isStreaming)
            }
            .padding(12)
            .background(.ultraThinMaterial)
        }
        .onAppear {
            isInputFocused = true
        }
    }

    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !conversation.isStreaming else { return }
        inputText = ""
        Task {
            await conversation.send(text)
        }
    }
}
```

- [ ] **Step 2: Add helper properties to ConversationManager**

Add to `ConversationManager.swift`:

```swift
// Add these computed properties to ConversationManager

/// Messages visible in the chat (excludes the system prompt).
var visibleMessages: [ChatMessage] {
    messages.filter { $0.role != .system }
}

/// Number of slides loaded.
var slideCount: Int {
    slides.count
}

/// Provider display name.
var providerName: String {
    provider.displayName
}
```

- [ ] **Step 3: Build to verify**

Run: `xcodebuild build -scheme Teleprompter -destination 'platform=macOS'`

- [ ] **Step 4: Commit**

```bash
git add Teleprompter/Teleprompter/Views/ScriptAssistant/ChatPanelView.swift Teleprompter/Teleprompter/Services/ConversationManager.swift
git commit -m "Add ChatPanelView with message list, streaming indicator, and input"
```

---

### Task 9: ScriptPreviewPanel

**Files:**
- Create: `Teleprompter/Teleprompter/Views/ScriptAssistant/ScriptPreviewPanel.swift`

- [ ] **Step 1: Implement script preview panel**

```swift
// Teleprompter/Views/ScriptAssistant/ScriptPreviewPanel.swift
import SwiftUI

struct ScriptPreviewPanel: View {
    let script: Script
    let totalSlides: Int
    let targetDurationMinutes: Int?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Script Preview")
                        .font(.system(size: 14, weight: .semibold))

                    if !script.sections.isEmpty {
                        Text("Live updating")
                            .font(.system(size: 10))
                            .foregroundStyle(.green)
                    }
                }

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial)

            Divider()

            // Sections
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    ForEach(script.sortedSections) { section in
                        previewSection(section)
                    }

                    // Show remaining slides as placeholders
                    let existingSlideNumbers = Set(script.sections.map(\.slideNumber))
                    ForEach(1...max(totalSlides, 1), id: \.self) { slideNum in
                        if !existingSlideNumbers.contains(slideNum) {
                            waitingSection(slideNumber: slideNum)
                        }
                    }
                }
                .padding(16)
            }

            Divider()

            // Progress bar
            progressBar
        }
    }

    private func previewSection(_ section: ScriptSection) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                SlidePillView(slideNumber: section.slideNumber, colorHex: section.accentColorHex)
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.green)
                Spacer()
                Text(ReadTimeEstimator.formatDuration(
                    ReadTimeEstimator.estimateDuration(for: section.content)
                ))
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
            }

            Text(section.content)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineSpacing(4)
        }
    }

    private func waitingSection(slideNumber: Int) -> some View {
        HStack(spacing: 6) {
            let accentColors = ["#4A9EFF", "#34C759", "#FF9500", "#FF2D55", "#AF52DE", "#5AC8FA", "#FFCC00", "#FF6B35"]
            SlidePillView(slideNumber: slideNumber, colorHex: accentColors[(slideNumber - 1) % accentColors.count])
            Text("Waiting for context...")
                .font(.system(size: 10))
                .foregroundStyle(.quaternary)
            Spacer()
        }
    }

    private var progressBar: some View {
        HStack(spacing: 8) {
            let readyCount = script.sections.count
            Text("\(readyCount) of \(totalSlides) slides ready")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)

            ProgressView(value: Double(readyCount), total: Double(max(totalSlides, 1)))
                .frame(width: 80)

            Spacer()

            let totalDuration = script.sortedSections.reduce(0.0) { total, section in
                total + ReadTimeEstimator.estimateDuration(for: section.content)
            }
            let durationText = ReadTimeEstimator.formatDuration(totalDuration)
            if let target = targetDurationMinutes {
                Text("\(durationText) / \(target) min target")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            } else {
                Text(durationText)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }
}
```

- [ ] **Step 2: Build to verify**

Run: `xcodebuild build -scheme Teleprompter -destination 'platform=macOS'`

- [ ] **Step 3: Commit**

```bash
git add Teleprompter/Teleprompter/Views/ScriptAssistant/ScriptPreviewPanel.swift
git commit -m "Add ScriptPreviewPanel with progress tracking"
```

---

### Task 10: ScriptAssistantView

**Files:**
- Create: `Teleprompter/Teleprompter/Views/ScriptAssistant/ScriptAssistantView.swift`

- [ ] **Step 1: Implement main assistant view**

```swift
// Teleprompter/Views/ScriptAssistant/ScriptAssistantView.swift
import SwiftUI
import SwiftData

struct ScriptAssistantView: View {
    let script: Script
    let slides: [SlideContent]
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var conversation: ConversationManager?
    @State private var targetMinutes: Int = 15
    @State private var hasStarted = false
    @State private var providerError: String?
    @State private var showingProviderError = false

    var body: some View {
        Group {
            if let conversation {
                HSplitView {
                    ChatPanelView(conversation: conversation)
                        .frame(minWidth: 350, idealWidth: 450)

                    ScriptPreviewPanel(
                        script: script,
                        totalSlides: slides.count,
                        targetDurationMinutes: targetMinutes
                    )
                    .frame(minWidth: 300, idealWidth: 350)
                }
            } else {
                startView
            }
        }
        .frame(minWidth: 750, minHeight: 500)
        .navigationTitle("Script Assistant -- \(script.name)")
        .alert("Provider Unavailable", isPresented: $showingProviderError) {
            Button("OK") {}
        } message: {
            Text(providerError ?? "")
        }
    }

    private var startView: some View {
        VStack(spacing: 20) {
            Text("Ready to generate your script")
                .font(.system(size: 18, weight: .semibold))

            Text("\(slides.count) slides loaded from your presentation")
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                Text("Target duration:")
                    .font(.system(size: 13))
                Picker("", selection: $targetMinutes) {
                    Text("5 min").tag(5)
                    Text("10 min").tag(10)
                    Text("15 min").tag(15)
                    Text("20 min").tag(20)
                    Text("30 min").tag(30)
                    Text("45 min").tag(45)
                    Text("60 min").tag(60)
                }
                .frame(width: 100)
            }

            Button("Start") {
                startConversation()
            }
            .buttonStyle(.glass)
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func startConversation() {
        let provider = ClaudeCLIProvider(model: .sonnet)

        guard provider.isAvailable else {
            providerError = "Claude Code CLI not found. Install it with: npm install -g @anthropic-ai/claude-code"
            showingProviderError = true
            return
        }

        let manager = ConversationManager(
            provider: provider,
            slides: slides,
            script: script,
            targetDurationMinutes: targetMinutes,
            modelContext: modelContext
        )

        conversation = manager
        hasStarted = true

        Task {
            await manager.start()
        }
    }
}
```

- [ ] **Step 2: Build to verify**

Run: `xcodebuild build -scheme Teleprompter -destination 'platform=macOS'`

- [ ] **Step 3: Commit**

```bash
git add Teleprompter/Teleprompter/Views/ScriptAssistant/ScriptAssistantView.swift
git commit -m "Add ScriptAssistantView with chat and preview split"
```

---

### Task 11: Wire Import Button and Navigation

**Files:**
- Modify: `Teleprompter/Teleprompter/Views/ScriptManager/ScriptSidebarView.swift`
- Modify: `Teleprompter/Teleprompter/Views/ScriptManager/ScriptDetailView.swift`
- Modify: `Teleprompter/Teleprompter/Views/ScriptManager/ScriptManagerView.swift`

- [ ] **Step 1: Add import and navigation state to ScriptManagerView**

Replace `ScriptManagerView.swift`:

```swift
// Teleprompter/Views/ScriptManager/ScriptManagerView.swift
import SwiftUI
import SwiftData

struct ScriptManagerView: View {
    @State private var selectedScript: Script?
    @State private var showingAssistant = false
    @State private var assistantScript: Script?
    @State private var assistantSlides: [SlideContent] = []
    @State private var importError: String?
    @State private var showingImportError = false
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        NavigationSplitView {
            ScriptSidebarView(
                selectedScript: $selectedScript,
                onImport: { importPPTX() }
            )
            .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 280)
        } detail: {
            if let script = selectedScript {
                ScriptDetailView(
                    script: script,
                    onRefineWithAI: { openAssistant(for: script) }
                )
            } else {
                ContentUnavailableView(
                    "No Script Selected",
                    systemImage: "doc.text.magnifyingglass",
                    description: Text("Select a script from the sidebar or create a new one.")
                )
            }
        }
        .frame(minWidth: 700, minHeight: 450)
        .sheet(isPresented: $showingAssistant) {
            if let script = assistantScript {
                ScriptAssistantView(script: script, slides: assistantSlides)
                    .frame(minWidth: 800, minHeight: 600)
            }
        }
        .alert("Import Error", isPresented: $showingImportError) {
            Button("OK") {}
        } message: {
            Text(importError ?? "Unknown error")
        }
    }

    private func importPPTX() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.init(filenameExtension: "pptx")!]
        panel.allowsMultipleSelection = false
        panel.message = "Select a PowerPoint presentation to import"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let result = try PPTXParser.parse(fileAt: url)

            let script = Script(name: result.fileName)
            let accentColors = ["#4A9EFF", "#34C759", "#FF9500", "#FF2D55", "#AF52DE", "#5AC8FA", "#FFCC00", "#FF6B35"]

            for slide in result.slides {
                let section = ScriptSection(
                    slideNumber: slide.slideNumber,
                    label: slide.title.isEmpty ? "Slide \(slide.slideNumber)" : slide.title,
                    content: slide.notes.isEmpty ? "" : slide.notes,
                    order: slide.slideNumber - 1,
                    accentColorHex: accentColors[(slide.slideNumber - 1) % accentColors.count]
                )
                script.sections.append(section)
            }

            modelContext.insert(script)
            selectedScript = script

            // Open assistant with slides
            assistantSlides = result.slides
            assistantScript = script
            showingAssistant = true

            if !result.warnings.isEmpty {
                importError = "Imported with warnings:\n" + result.warnings.joined(separator: "\n")
                showingImportError = true
            }
        } catch {
            importError = error.localizedDescription
            showingImportError = true
        }
    }

    private func openAssistant(for script: Script) {
        // Build SlideContent from existing sections
        assistantSlides = script.sortedSections.map { section in
            SlideContent(
                slideNumber: section.slideNumber,
                title: section.label,
                bodyText: section.content,
                notes: ""
            )
        }
        assistantScript = script
        showingAssistant = true
    }
}

#Preview {
    ScriptManagerView()
        .modelContainer(PreviewSampleData.container)
}
```

- [ ] **Step 2: Update ScriptSidebarView to accept onImport callback**

In `ScriptSidebarView.swift`:

1. Add `var onImport: () -> Void = {}` right after `@State private var searchText = ""` (line 9)
2. Replace `Button("Import") { /* Plan 2: PPTX import */ }` with `Button("Import") { onImport() }`
3. Update the preview to pass the new parameter:

```swift
#Preview {
    ScriptSidebarView(selectedScript: .constant(nil), onImport: {})
        .modelContainer(PreviewSampleData.container)
        .frame(width: 220)
}
```

- [ ] **Step 3: Update ScriptDetailView to accept onRefineWithAI callback**

In `ScriptDetailView.swift`:

1. Add `var onRefineWithAI: () -> Void = {}` right after `@State private var isEditingName = false` (line 7)
2. Replace `Button("Refine with AI") { // Plan 2: open Script Assistant }` with `Button("Refine with AI") { onRefineWithAI() }`
3. Update the preview to pass the new parameter:

```swift
#Preview {
    ScriptDetailView(script: PreviewSampleData.sampleScript(), onRefineWithAI: {})
        .modelContainer(PreviewSampleData.container)
        .frame(width: 700, height: 500)
}
```

- [ ] **Step 4: Build and verify**

Run: `xcodebuild build -scheme Teleprompter -destination 'platform=macOS'`

- [ ] **Step 5: Commit**

```bash
git add Teleprompter/Teleprompter/Views/ScriptManager/ScriptManagerView.swift Teleprompter/Teleprompter/Views/ScriptManager/ScriptSidebarView.swift Teleprompter/Teleprompter/Views/ScriptManager/ScriptDetailView.swift
git commit -m "Wire Import and Refine buttons to PPTX parser and Script Assistant"
```

---

### Task 12: Add targetDuration to Script Model

**Files:**
- Modify: `Teleprompter/Teleprompter/Models/Script.swift`

- [ ] **Step 1: Add targetDuration property**

Add to `Script.swift`:

```swift
var targetDuration: Double?  // desired talk length in seconds; nil = no target
```

Add to the init:

```swift
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
```

- [ ] **Step 2: Run tests to verify nothing broke**

Run: `xcodebuild test -scheme Teleprompter -destination 'platform=macOS'`
Expected: ALL PASS (existing tests use default `nil` value)

- [ ] **Step 3: Commit**

```bash
git add Teleprompter/Teleprompter/Models/Script.swift
git commit -m "Add optional targetDuration to Script model"
```

---

### Task 13: End-to-End Smoke Test

- [ ] **Step 1: Run all tests**

Run: `xcodebuild test -scheme Teleprompter -destination 'platform=macOS'`
Expected: ALL PASS

- [ ] **Step 2: Run app and test import flow**

Run: `Cmd+R`
Verify:
1. Click "Import" in sidebar -- file picker opens
2. Select a .pptx file -- slides are parsed, script is created
3. Script Assistant sheet opens with slide count and target duration selector
4. Click "Start" -- Claude CLI is invoked, streaming response appears
5. LLM asks about slides, generates script text
6. Script preview panel shows generated sections with progress
7. Close the assistant -- script sections persist in the Script Manager detail view
8. Click "Refine with AI" on an existing script -- assistant opens with current sections as context

- [ ] **Step 3: Fix any issues found during smoke test**

- [ ] **Step 4: Final commit**

```bash
# Check what changed, then stage only those files
git status
git add <specific-files-from-git-status>
git commit -m "Polish Script Assistant after smoke test"
```
