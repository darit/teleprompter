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
