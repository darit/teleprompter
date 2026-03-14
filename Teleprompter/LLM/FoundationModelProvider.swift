// Teleprompter/LLM/FoundationModelProvider.swift
import Foundation
import FoundationModels

@MainActor
final class FoundationModelProvider: LLMProvider, @unchecked Sendable {

    var displayName: String { "Apple On-Device (Built-in)" }

    var supportsParallelGeneration: Bool { false }

    var contextWindowSize: Int? { 4096 }

    var isAvailable: Bool {
        get async {
            let availability = SystemLanguageModel.default.availability
            switch availability {
            case .available:
                return true
            default:
                return false
            }
        }
    }

    // Retain the session for multi-turn conversation support.
    private var session: LanguageModelSession?

    func stream(messages: [ChatMessage]) async throws -> AsyncStream<String> {
        // Extract system prompt for Instructions
        let systemContent = messages.first { $0.role == .system }?.content ?? ""

        // Detect independent (stateless) calls: only system + user messages,
        // no conversation history. These need a fresh session to avoid context
        // overflow from accumulated multi-turn state (e.g. "Generate All" flow).
        let nonSystemMessages = messages.filter { $0.role != .system }
        let isIndependentCall = nonSystemMessages.count == 1 && nonSystemMessages.first?.role == .user

        if session == nil || isIndependentCall {
            session = LanguageModelSession(instructions: systemContent)
        }

        // Build the user message (last user message in the conversation)
        let userMessage = messages.last { $0.role == .user }?.content ?? ""

        guard let currentSession = session else {
            return AsyncStream { $0.finish() }
        }

        return AsyncStream { continuation in
            Task {
                do {
                    let stream = currentSession.streamResponse(to: userMessage)
                    var lastLength = 0
                    for try await partial in stream {
                        // partial.content is the cumulative text so far;
                        // yield only the new characters since last chunk.
                        let fullText = partial.content
                        if fullText.count > lastLength {
                            let newText = String(fullText.dropFirst(lastLength))
                            continuation.yield(newText)
                            lastLength = fullText.count
                        }
                    }
                } catch {
                    continuation.yield("\n\n[Error: \(error.localizedDescription)]")
                }
                continuation.finish()
            }
        }
    }

    /// Reset the session (call when clearing chat history).
    func resetSession() {
        session = nil
    }
}
