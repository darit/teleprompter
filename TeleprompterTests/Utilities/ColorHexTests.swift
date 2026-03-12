import Testing
import SwiftUI
@testable import Teleprompter

@Suite("Color Hex Conversion")
struct ColorHexTests {

    @Test("creates Color from valid hex string")
    func testFromHex() {
        let color = Color(hex: "#4A9EFF")
        #expect(color != nil)
    }

    @Test("returns nil for invalid hex")
    func testInvalidHex() {
        let color = Color(hex: "not-a-color")
        #expect(color == nil)
    }

    @Test("handles hex without hash prefix")
    func testWithoutHash() {
        let color = Color(hex: "4A9EFF")
        #expect(color != nil)
    }
}
