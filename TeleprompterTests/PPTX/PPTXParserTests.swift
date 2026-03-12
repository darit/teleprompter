// TeleprompterTests/PPTX/PPTXParserTests.swift
import Testing
import Foundation
@testable import Teleprompter

@Suite("PPTX Parser")
struct PPTXParserTests {

    @Test("rejects non-ZIP file")
    func testRejectsNonZip() async throws {
        let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent("fake.pptx")
        try "not a zip file".data(using: .utf8)!.write(to: tempFile)
        defer { try? FileManager.default.removeItem(at: tempFile) }

        do {
            _ = try PPTXParser.parse(fileAt: tempFile)
            Issue.record("Expected PPTXParseError.invalidFile")
        } catch is PPTXParseError {
            // expected
        }
    }

    @Test("extracts text from slide XML")
    func testExtractTextFromSlideXML() {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <p:sld xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main"
               xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main"
               xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
          <p:cSld>
            <p:spTree>
              <p:sp>
                <p:nvSpPr><p:nvPr><p:ph type="title"/></p:nvPr></p:nvSpPr>
                <p:txBody>
                  <a:p><a:r><a:t>My Title</a:t></a:r></a:p>
                </p:txBody>
              </p:sp>
              <p:sp>
                <p:nvSpPr><p:nvPr><p:ph type="body"/></p:nvPr></p:nvSpPr>
                <p:txBody>
                  <a:p><a:r><a:t>Bullet one</a:t></a:r></a:p>
                  <a:p><a:r><a:t>Bullet two</a:t></a:r></a:p>
                </p:txBody>
              </p:sp>
            </p:spTree>
          </p:cSld>
        </p:sld>
        """
        let data = xml.data(using: .utf8)!
        let result = PPTXParser.extractSlideContent(from: data, slideNumber: 1)

        #expect(result.title == "My Title")
        #expect(result.bodyText.contains("Bullet one"))
        #expect(result.bodyText.contains("Bullet two"))
    }

    @Test("extracts notes from notes XML")
    func testExtractNotes() {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <p:notes xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main"
                 xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main">
          <p:cSld>
            <p:spTree>
              <p:sp>
                <p:nvSpPr><p:nvPr><p:ph type="body" idx="1"/></p:nvPr></p:nvSpPr>
                <p:txBody>
                  <a:p><a:r><a:t>Speaker notes here</a:t></a:r></a:p>
                </p:txBody>
              </p:sp>
            </p:spTree>
          </p:cSld>
        </p:notes>
        """
        let data = xml.data(using: .utf8)!
        let notes = PPTXParser.extractNotes(from: data)

        #expect(notes == "Speaker notes here")
    }
}
