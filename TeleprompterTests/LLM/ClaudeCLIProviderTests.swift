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
