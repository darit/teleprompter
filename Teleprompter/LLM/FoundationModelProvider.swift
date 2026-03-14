// Teleprompter/LLM/FoundationModelProvider.swift
import Foundation
import FoundationModels

final class FoundationModelProvider: LLMProvider, @unchecked Sendable {

    var displayName: String { "Apple On-Device (Built-in)" }

    var supportsParallelGeneration: Bool { false }

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

        // Create session with system instructions (retain for multi-turn)
        if session == nil {
            session = LanguageModelSession(instructions: systemContent)
        }

        // Build the user message (last user message in the conversation)
        let userMessage = messages.last { $0.role == .user }?.content ?? ""

        let currentSession = session!

        return AsyncStream { continuation in
            Task {
                do {
                    let stream = currentSession.streamResponse(to: userMessage)
                    for try await partial in stream {
                        let text = String(describing: partial)
                        continuation.yield(text)
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
