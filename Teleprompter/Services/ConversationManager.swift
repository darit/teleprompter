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
                let trimmed = remaining.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    segments.append(ResponseSegment(type: .text, content: trimmed))
                }
                remaining = ""
            }
        }

        return segments
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
}
