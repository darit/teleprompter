import Testing
import Foundation
@testable import Teleprompter

@Suite("ScriptSection Model")
struct ScriptSectionTests {

    @Test("initializes with all required properties")
    func testInit() {
        let section = ScriptSection(
            slideNumber: 1,
            label: "Introduction",
            content: "Welcome everyone to this presentation.",
            order: 0,
            accentColorHex: "#4A9EFF",
            isAIRefined: false
        )

        #expect(section.slideNumber == 1)
        #expect(section.label == "Introduction")
        #expect(section.content == "Welcome everyone to this presentation.")
        #expect(section.order == 0)
        #expect(section.accentColorHex == "#4A9EFF")
        #expect(section.isAIRefined == false)
    }
}
