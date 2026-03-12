import Foundation

protocol LLMProvider: Sendable {
    /// Stream a response from the LLM given a conversation history.
    func stream(messages: [ChatMessage]) async throws -> AsyncStream<String>

    /// Human-readable name for this provider (e.g. "Claude Code CLI (Sonnet)").
    var displayName: String { get }

    /// Whether this provider is currently available (e.g. CLI found in PATH).
    var isAvailable: Bool { get }
}
