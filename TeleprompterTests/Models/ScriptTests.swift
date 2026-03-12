import Testing
import Foundation
@testable import Teleprompter

@Suite("Script Model")
struct ScriptTests {

    @Test("initializes with name and empty sections")
    func testInitDefaults() {
        let script = Script(name: "Test Script")

        #expect(script.name == "Test Script")
        #expect(script.sections.isEmpty)
        #expect(script.scrollSpeed == 1.0)
        #expect(script.fontSize == 16.0)
    }

    @Test("stores sections in order")
    func testSectionsOrdering() {
        let script = Script(name: "Ordered")
        let s1 = ScriptSection(slideNumber: 1, label: "Intro", content: "Hello", order: 0, accentColorHex: "#FF0000")
        let s2 = ScriptSection(slideNumber: 2, label: "Body", content: "Main", order: 1, accentColorHex: "#00FF00")
        script.sections = [s1, s2]

        let sorted = script.sortedSections
        #expect(sorted.count == 2)
        #expect(sorted[0].label == "Intro")
        #expect(sorted[1].label == "Body")
    }

    @Test("modifiedAt updates are tracked")
    func testDates() {
        let script = Script(name: "Dated")
        #expect(script.createdAt <= Date.now)
        #expect(script.modifiedAt <= Date.now)
    }
}
