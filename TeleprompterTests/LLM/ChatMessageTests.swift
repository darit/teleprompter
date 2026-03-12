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
