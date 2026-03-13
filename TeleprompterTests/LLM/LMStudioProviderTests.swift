// TeleprompterTests/LLM/LMStudioProviderTests.swift
import Testing
import Foundation
@testable import Teleprompter

@Suite("LM Studio Provider")
struct LMStudioProviderTests {

    // MARK: - Display Name

    @Test("display name without model")
    func testDisplayNameDefault() {
        let provider = LMStudioProvider()
        #expect(provider.displayName == "LM Studio")
    }

    @Test("display name includes model when specified")
    func testDisplayNameWithModel() {
        let provider = LMStudioProvider(modelName: "llama-3.1-8b")
        #expect(provider.displayName == "LM Studio (llama-3.1-8b)")
    }

    // MARK: - Request Body

    @Test("request body contains messages and stream flag")
    func testRequestBodyStructure() throws {
        let provider = LMStudioProvider(modelName: "test-model")
        let messages = [
            ChatMessage(role: .system, content: "You are helpful."),
            ChatMessage(role: .user, content: "Hello"),
        ]

        let body = provider.buildRequestBody(messages: messages)

        #expect(body["stream"] as? Bool == true)
        #expect(body["model"] as? String == "test-model")

        let messageDicts = try #require(body["messages"] as? [[String: String]])
        #expect(messageDicts.count == 2)
        #expect(messageDicts[0]["role"] == "system")
        #expect(messageDicts[0]["content"] == "You are helpful.")
        #expect(messageDicts[1]["role"] == "user")
        #expect(messageDicts[1]["content"] == "Hello")
    }

    @Test("request body omits model when not specified")
    func testRequestBodyNoModel() {
        let provider = LMStudioProvider()
        let messages = [ChatMessage(role: .user, content: "Hi")]
        let body = provider.buildRequestBody(messages: messages)

        #expect(body["model"] == nil)
        #expect(body["stream"] as? Bool == true)
    }

    // MARK: - SSE Parsing

    @Test("parses content from SSE data line")
    func testParseSSEContentLine() {
        let line = "data: {\"id\":\"x\",\"object\":\"chat.completion.chunk\",\"choices\":[{\"delta\":{\"content\":\"Hello\"},\"index\":0}]}"
        let result = LMStudioProvider.parseSSELine(line)
        #expect(result == "Hello")
    }

    @Test("returns nil for DONE sentinel")
    func testParseSSEDone() {
        let result = LMStudioProvider.parseSSELine("data: [DONE]")
        #expect(result == nil)
    }

    @Test("returns nil for non-data lines")
    func testParseSSENonDataLine() {
        #expect(LMStudioProvider.parseSSELine("") == nil)
        #expect(LMStudioProvider.parseSSELine(": keep-alive") == nil)
        #expect(LMStudioProvider.parseSSELine("event: message") == nil)
    }

    @Test("returns nil when delta has no content")
    func testParseSSEEmptyDelta() {
        let line = "data: {\"id\":\"x\",\"object\":\"chat.completion.chunk\",\"choices\":[{\"delta\":{},\"index\":0}]}"
        let result = LMStudioProvider.parseSSELine(line)
        #expect(result == nil)
    }

    @Test("returns nil for malformed JSON")
    func testParseSSEMalformedJSON() {
        let result = LMStudioProvider.parseSSELine("data: not-json")
        #expect(result == nil)
    }

    @Test("parses content with special characters")
    func testParseSSESpecialCharacters() {
        let line = "data: {\"choices\":[{\"delta\":{\"content\":\"Hello, \\\"world\\\"!\\n\"},\"index\":0}]}"
        let result = LMStudioProvider.parseSSELine(line)
        #expect(result == "Hello, \"world\"!\n")
    }
}
