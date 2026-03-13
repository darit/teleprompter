import Testing
import Foundation
@testable import Teleprompter

@Suite("TeleprompterState")
struct TeleprompterStateTests {

    @Test("initial state is paused at top")
    func testInitialState() {
        let sections = TeleprompterStateTests.sampleSections()
        let state = TeleprompterState(sections: sections, fontSize: 24, scrollSpeed: 1.0)

        #expect(state.isPlaying == false)
        #expect(state.scrollOffset == 0)
        #expect(state.currentSectionIndex == 0)
        #expect(state.opacity == 1.0)
        #expect(state.isClickThrough == false)
    }

    @Test("play and pause toggle")
    func testPlayPause() {
        let state = TeleprompterState(sections: sampleSections(), fontSize: 24, scrollSpeed: 1.0)

        state.togglePlayPause()
        #expect(state.isPlaying == true)

        state.togglePlayPause()
        #expect(state.isPlaying == false)
    }

    @Test("jump forward advances section index")
    func testJumpForward() {
        let state = TeleprompterState(sections: sampleSections(), fontSize: 24, scrollSpeed: 1.0)

        state.jumpForward()
        #expect(state.currentSectionIndex == 1)

        state.jumpForward()
        #expect(state.currentSectionIndex == 2)

        // Should not go past last section
        state.jumpForward()
        #expect(state.currentSectionIndex == 2)
    }

    @Test("jump backward decreases section index")
    func testJumpBackward() {
        let state = TeleprompterState(sections: sampleSections(), fontSize: 24, scrollSpeed: 1.0)

        state.jumpForward()
        state.jumpForward()
        #expect(state.currentSectionIndex == 2)

        state.jumpBackward()
        #expect(state.currentSectionIndex == 1)

        state.jumpBackward()
        #expect(state.currentSectionIndex == 0)

        // Should not go below 0
        state.jumpBackward()
        #expect(state.currentSectionIndex == 0)
    }

    @Test("speed adjustment clamps to range")
    func testSpeedAdjustment() {
        let state = TeleprompterState(sections: sampleSections(), fontSize: 24, scrollSpeed: 1.0)

        state.increaseSpeed()
        #expect(state.scrollSpeed == 1.25)

        state.decreaseSpeed()
        #expect(state.scrollSpeed == 1.0)

        // Should not go below minimum
        state.scrollSpeed = 0.25
        state.decreaseSpeed()
        #expect(state.scrollSpeed == 0.25)

        // Should not exceed maximum
        state.scrollSpeed = 3.0
        state.increaseSpeed()
        #expect(state.scrollSpeed == 3.0)
    }

    @Test("opacity clamps to range")
    func testOpacity() {
        let state = TeleprompterState(sections: sampleSections(), fontSize: 24, scrollSpeed: 1.0)

        state.increaseOpacity()
        #expect(state.opacity == 1.0) // already at max

        state.opacity = 0.5
        state.decreaseOpacity()
        #expect(state.opacity == 0.4)

        state.opacity = 0.2
        state.decreaseOpacity()
        #expect(state.opacity == 0.2) // clamp at min
    }

    @Test("click-through toggle")
    func testClickThrough() {
        let state = TeleprompterState(sections: sampleSections(), fontSize: 24, scrollSpeed: 1.0)
        #expect(state.isClickThrough == false)

        state.toggleClickThrough()
        #expect(state.isClickThrough == true)

        state.toggleClickThrough()
        #expect(state.isClickThrough == false)
    }

    @Test("full script text concatenates sections")
    func testFullScriptText() {
        let state = TeleprompterState(sections: sampleSections(), fontSize: 24, scrollSpeed: 1.0)
        let text = state.fullScriptText
        #expect(text.contains("Introduction text"))
        #expect(text.contains("Overview text"))
        #expect(text.contains("Conclusion text"))
    }

    @Test("section offsets computed for navigation")
    func testSectionOffsets() {
        let state = TeleprompterState(sections: sampleSections(), fontSize: 24, scrollSpeed: 1.0)
        #expect(state.sectionStartIndices.count == 3)
        #expect(state.sectionStartIndices[0] == 0)
    }

    // MARK: - Helpers

    static func sampleSections() -> [TeleprompterSection] {
        [
            TeleprompterSection(slideNumber: 1, label: "Introduction", content: "Introduction text here.", accentColorHex: "#4A9EFF"),
            TeleprompterSection(slideNumber: 2, label: "Overview", content: "Overview text goes here.", accentColorHex: "#34C759"),
            TeleprompterSection(slideNumber: 3, label: "Conclusion", content: "Conclusion text for the end.", accentColorHex: "#FF9500"),
        ]
    }

    func sampleSections() -> [TeleprompterSection] {
        Self.sampleSections()
    }
}
