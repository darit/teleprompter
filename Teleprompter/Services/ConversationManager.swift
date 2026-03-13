// Teleprompter/Services/ConversationManager.swift
import Foundation
import SwiftData

@Observable
final class ConversationManager {
    var messages: [ChatMessage] = []
    var isStreaming = false
    var currentStreamingText = ""
    var error: String?
    var activelyStreamingSlideNumber: Int?

    /// Called when script sections are updated (for preview refresh).
    var onSectionsChanged: (() -> Void)?

    private var streamingTask: Task<Void, Never>?

    private(set) var provider: any LLMProvider
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

        // Add system prompt with slide images for vision-capable models
        let systemPrompt = PromptTemplates.systemPrompt(
            slides: slides,
            targetDurationMinutes: targetDurationMinutes
        )
        let allSlideImages = slides.flatMap(\.images)
        messages.append(ChatMessage(role: .system, content: systemPrompt, images: allSlideImages))

        // Restore persisted chat history
        let sorted = script.chatHistory.sorted { $0.order < $1.order }
        for persisted in sorted {
            messages.append(persisted.toChatMessage())
        }
    }

    /// Send a user message and stream the response.
    @MainActor
    func send(_ userMessage: String) async {
        let userMsg = ChatMessage(role: .user, content: userMessage)
        messages.append(userMsg)
        persistMessage(userMsg)
        await streamResponse()
    }

    /// Start the conversation (sends initial prompt to get LLM's opening message).
    @MainActor
    func start() async {
        await streamResponse()
    }

    /// Clear all chat history (keeps system prompt).
    @MainActor
    func clearHistory() {
        // Remove all non-system messages
        messages.removeAll { $0.role != .system }

        // Clear persisted history
        for persisted in script.chatHistory {
            modelContext.delete(persisted)
        }
        script.chatHistory.removeAll()

        error = nil
        currentStreamingText = ""
    }

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
                let segments = Self.parseResponse(partial)
                for segment in segments {
                    if case .script(let slideNumber) = segment.type {
                        updateScriptSection(slideNumber: slideNumber, content: segment.content, updateTimestamp: true)
                    }
                }
            }
            currentStreamingText = ""
            isStreaming = false
            activelyStreamingSlideNumber = nil
        }
    }

    @MainActor
    func deleteMessage(_ message: ChatMessage) {
        guard let index = messages.firstIndex(where: { $0.id == message.id }) else { return }
        messages.remove(at: index)

        // Remove from persistence
        if let persisted = script.chatHistory.first(where: {
            $0.role == message.role.rawValue && $0.content == message.content
        }) {
            modelContext.delete(persisted)
            script.chatHistory.removeAll { $0 === persisted }
        }
        try? modelContext.save()
    }

    @MainActor
    func removeLastAssistantMessage() {
        guard let lastIndex = messages.lastIndex(where: { $0.role == .assistant }) else { return }
        let removedMessage = messages.remove(at: lastIndex)
        if let lastPersisted = script.chatHistory
            .sorted(by: { $0.order < $1.order })
            .last(where: { $0.role == "assistant" }) {
            modelContext.delete(lastPersisted)
            script.chatHistory.removeAll { $0 === lastPersisted }
        }
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
    func generateSlide(_ slideNumber: Int) async {
        let slide = slides.first { $0.slideNumber == slideNumber }
        let slideTitle = slide?.title ?? "Slide \(slideNumber)"
        let prompt = "Generate the teleprompter script for slide \(slideNumber) (\(slideTitle)). Use the slide content, speaker notes, and our conversation so far as context. Output only the script block for this slide."
        await send(prompt)
    }

    @MainActor
    func regenerateLastResponse() async {
        removeLastAssistantMessage()
        await streamResponse()
    }

    @MainActor
    private func streamResponse() async {
        isStreaming = true
        currentStreamingText = ""
        error = nil

        streamingTask = Task {
            do {
                let stream = try await provider.stream(messages: messages)
                var buffer = ""
                var lastPreviewUpdate = Date.distantPast

                for await chunk in stream {
                    if Task.isCancelled { break }
                    buffer += chunk
                    currentStreamingText = buffer

                    // Throttle live preview parsing to at most every 300ms
                    let now = Date()
                    if now.timeIntervalSince(lastPreviewUpdate) >= 0.3 {
                        lastPreviewUpdate = now
                        let parseResult = Self.parseStreamingBuffer(buffer)
                        activelyStreamingSlideNumber = parseResult.activeSlideNumber
                        if let slideNum = parseResult.activeSlideNumber, let partial = parseResult.partialContent {
                            updateScriptSection(slideNumber: slideNum, content: partial)
                        }
                    }
                }

                // Final parse after stream ends
                let finalParse = Self.parseStreamingBuffer(buffer)
                if let slideNum = finalParse.activeSlideNumber, let partial = finalParse.partialContent {
                    updateScriptSection(slideNumber: slideNum, content: partial)
                }

                guard !Task.isCancelled else { return }

                let response = currentStreamingText.trimmingCharacters(in: .whitespacesAndNewlines)
                let assistantMsg = ChatMessage(role: .assistant, content: response)
                messages.append(assistantMsg)
                persistMessage(assistantMsg)

                // Parse response for script markers and update sections
                let segments = Self.parseResponse(response)
                for segment in segments {
                    if case .script(let slideNumber) = segment.type {
                        updateScriptSection(slideNumber: slideNumber, content: segment.content, updateTimestamp: true)
                    }
                }

                currentStreamingText = ""
            } catch {
                if !Task.isCancelled {
                    self.error = error.localizedDescription
                }
            }

            isStreaming = false
            activelyStreamingSlideNumber = nil
        }

        await streamingTask?.value
    }

    private func persistMessage(_ message: ChatMessage) {
        let order = script.chatHistory.count
        let persisted = PersistedChatMessage.from(message, order: order)
        script.chatHistory.append(persisted)
        script.modifiedAt = .now
        try? modelContext.save()
    }

    private func updateScriptSection(slideNumber: Int, content: String, updateTimestamp: Bool = false) {
        if let existing = script.sections.first(where: { $0.slideNumber == slideNumber }) {
            existing.content = content
            existing.isAIRefined = true
        } else {
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
        if updateTimestamp {
            script.modifiedAt = .now
            onSectionsChanged?()
        }
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
                let trimmed = remaining.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    segments.append(ResponseSegment(type: .text, content: trimmed))
                }
                remaining = ""
            }
        }

        return segments
    }

    // MARK: - Streaming Buffer Parsing

    struct StreamingParseResult {
        let activeSlideNumber: Int?
        let partialContent: String?
    }

    static func parseStreamingBuffer(_ buffer: String) -> StreamingParseResult {
        let startPattern = /\[SCRIPT_START\s+slide=(\d+)\]/
        let endMarker = "[SCRIPT_END]"

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

        if afterStart.contains(endMarker) {
            return StreamingParseResult(activeSlideNumber: nil, partialContent: nil)
        }

        let partialContent = afterStart.trimmingCharacters(in: .whitespacesAndNewlines)
        return StreamingParseResult(
            activeSlideNumber: slideNumber,
            partialContent: partialContent.isEmpty ? nil : partialContent
        )
    }

    // MARK: - Computed Properties for Views

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

    /// Swap to a different provider without losing conversation history.
    func switchProvider(_ newProvider: any LLMProvider) {
        provider = newProvider
    }
}
