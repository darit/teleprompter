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
