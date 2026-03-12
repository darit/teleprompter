// Teleprompter/PPTX/PPTXParser.swift
import Foundation

enum PPTXParser {

    /// Parse a PPTX file and extract slide content.
    static func parse(fileAt url: URL) throws -> PPTXParseResult {
        let fileManager = FileManager.default
        let tempDir = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)

        defer { try? fileManager.removeItem(at: tempDir) }

        // PPTX is a ZIP archive -- unzip it
        do {
            try fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true)
            try fileManager.unzipItem(at: url, to: tempDir)
        } catch {
            throw PPTXParseError.invalidFile("Could not decompress file: \(error.localizedDescription)")
        }

        // Check for encryption marker
        let encryptionFile = tempDir.appendingPathComponent("EncryptedPackage")
        if fileManager.fileExists(atPath: encryptionFile.path) {
            throw PPTXParseError.encrypted
        }

        // Read presentation.xml for slide ordering
        let presentationURL = tempDir.appendingPathComponent("ppt/presentation.xml")
        guard let presentationData = try? Data(contentsOf: presentationURL) else {
            throw PPTXParseError.invalidFile("Missing ppt/presentation.xml")
        }

        let slideIds = extractSlideRelationshipIds(from: presentationData)

        // Read relationships to map rIds to slide file paths
        let relsURL = tempDir.appendingPathComponent("ppt/_rels/presentation.xml.rels")
        guard let relsData = try? Data(contentsOf: relsURL) else {
            throw PPTXParseError.invalidFile("Missing presentation relationships")
        }
        let rIdToFile = extractRelationships(from: relsData)

        var slides: [SlideContent] = []
        var warnings: [String] = []

        for (index, rId) in slideIds.enumerated() {
            let slideNumber = index + 1
            guard let slideFile = rIdToFile[rId] else {
                warnings.append("Slide \(slideNumber): could not resolve relationship \(rId)")
                continue
            }

            let slidePath = "ppt/\(slideFile)"
            let slideURL = tempDir.appendingPathComponent(slidePath)

            guard let slideData = try? Data(contentsOf: slideURL) else {
                warnings.append("Slide \(slideNumber): could not read \(slidePath)")
                continue
            }

            var slide = extractSlideContent(from: slideData, slideNumber: slideNumber)

            // Try to read notes
            let noteFile = slideFile.replacingOccurrences(of: "slides/slide", with: "notesSlides/notesSlide")
            let notePath = "ppt/\(noteFile)"
            let noteURL = tempDir.appendingPathComponent(notePath)
            if let noteData = try? Data(contentsOf: noteURL) {
                let notes = extractNotes(from: noteData)
                slide = SlideContent(slideNumber: slide.slideNumber, title: slide.title, bodyText: slide.bodyText, notes: notes)
            }

            slides.append(slide)
        }

        if slides.isEmpty {
            throw PPTXParseError.noSlidesFound
        }

        let fileName = url.deletingPathExtension().lastPathComponent
        return PPTXParseResult(fileName: fileName, slides: slides, warnings: warnings)
    }

    // MARK: - XML Extraction (internal for testing)

    /// Extract text content from a slide XML.
    static func extractSlideContent(from data: Data, slideNumber: Int) -> SlideContent {
        let parser = SlideXMLParser(data: data)
        parser.parse()
        return SlideContent(
            slideNumber: slideNumber,
            title: parser.titleText.joined(separator: " "),
            bodyText: parser.bodyParagraphs.joined(separator: "\n"),
            notes: ""
        )
    }

    /// Extract notes text from a notes slide XML.
    static func extractNotes(from data: Data) -> String {
        let parser = NotesXMLParser(data: data)
        parser.parse()
        return parser.notesParagraphs.joined(separator: "\n")
    }

    /// Extract ordered slide relationship IDs from presentation.xml.
    private static func extractSlideRelationshipIds(from data: Data) -> [String] {
        let parser = PresentationXMLParser(data: data)
        parser.parse()
        return parser.slideRelationshipIds
    }

    /// Extract relationship ID to target file mapping from .rels XML.
    private static func extractRelationships(from data: Data) -> [String: String] {
        let parser = RelsXMLParser(data: data)
        parser.parse()
        return parser.relationships
    }
}

// MARK: - Slide XML Parser

private class SlideXMLParser: NSObject, XMLParserDelegate {
    private let xmlParser: XMLParser
    var titleText: [String] = []
    var bodyParagraphs: [String] = []

    private var currentText = ""
    private var isInTitleShape = false
    private var isInBodyShape = false
    private var isCollectingText = false
    private var currentParagraphTexts: [String] = []
    private var placeholderType: String?

    init(data: Data) {
        self.xmlParser = XMLParser(data: data)
        super.init()
        xmlParser.delegate = self
    }

    func parse() {
        xmlParser.parse()
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?,
                attributes attributeDict: [String: String] = [:]) {
        let localName = elementName.components(separatedBy: ":").last ?? elementName

        if localName == "ph" {
            placeholderType = attributeDict["type"]
        }

        if localName == "txBody" {
            if placeholderType == "title" || placeholderType == "ctrTitle" {
                isInTitleShape = true
            } else {
                isInBodyShape = true
            }
        }

        if localName == "p" && (isInTitleShape || isInBodyShape) {
            currentParagraphTexts = []
        }

        if localName == "t" {
            isCollectingText = true
            currentText = ""
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if isCollectingText {
            currentText += string
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?) {
        let localName = elementName.components(separatedBy: ":").last ?? elementName

        if localName == "t" {
            isCollectingText = false
            if isInTitleShape || isInBodyShape {
                currentParagraphTexts.append(currentText)
            }
        }

        if localName == "p" {
            let paragraphText = currentParagraphTexts.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
            if !paragraphText.isEmpty {
                if isInTitleShape {
                    titleText.append(paragraphText)
                } else if isInBodyShape {
                    bodyParagraphs.append(paragraphText)
                }
            }
            currentParagraphTexts = []
        }

        if localName == "txBody" {
            isInTitleShape = false
            isInBodyShape = false
        }

        if localName == "sp" {
            placeholderType = nil
        }
    }
}

// MARK: - Notes XML Parser

private class NotesXMLParser: NSObject, XMLParserDelegate {
    private let xmlParser: XMLParser
    var notesParagraphs: [String] = []

    private var isInNotesBody = false
    private var isCollectingText = false
    private var currentText = ""
    private var currentParagraphTexts: [String] = []
    private var placeholderType: String?
    private var placeholderIdx: String?

    init(data: Data) {
        self.xmlParser = XMLParser(data: data)
        super.init()
        xmlParser.delegate = self
    }

    func parse() {
        xmlParser.parse()
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?,
                attributes attributeDict: [String: String] = [:]) {
        let localName = elementName.components(separatedBy: ":").last ?? elementName

        if localName == "ph" {
            placeholderType = attributeDict["type"]
            placeholderIdx = attributeDict["idx"]
        }

        if localName == "txBody" {
            // Notes body is type="body" with idx="1"
            if placeholderType == "body" && placeholderIdx == "1" {
                isInNotesBody = true
            }
        }

        if localName == "p" && isInNotesBody {
            currentParagraphTexts = []
        }

        if localName == "t" {
            isCollectingText = true
            currentText = ""
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if isCollectingText {
            currentText += string
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?) {
        let localName = elementName.components(separatedBy: ":").last ?? elementName

        if localName == "t" {
            isCollectingText = false
            if isInNotesBody {
                currentParagraphTexts.append(currentText)
            }
        }

        if localName == "p" && isInNotesBody {
            let text = currentParagraphTexts.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                notesParagraphs.append(text)
            }
            currentParagraphTexts = []
        }

        if localName == "txBody" {
            isInNotesBody = false
        }

        if localName == "sp" {
            placeholderType = nil
            placeholderIdx = nil
        }
    }
}

// MARK: - Presentation XML Parser

private class PresentationXMLParser: NSObject, XMLParserDelegate {
    private let xmlParser: XMLParser
    var slideRelationshipIds: [String] = []

    init(data: Data) {
        self.xmlParser = XMLParser(data: data)
        super.init()
        xmlParser.delegate = self
    }

    func parse() {
        xmlParser.parse()
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?,
                attributes attributeDict: [String: String] = [:]) {
        let localName = elementName.components(separatedBy: ":").last ?? elementName

        if localName == "sldId", let rId = attributeDict["r:id"] {
            slideRelationshipIds.append(rId)
        }
    }
}

// MARK: - Relationships XML Parser

private class RelsXMLParser: NSObject, XMLParserDelegate {
    private let xmlParser: XMLParser
    var relationships: [String: String] = [:]

    init(data: Data) {
        self.xmlParser = XMLParser(data: data)
        super.init()
        xmlParser.delegate = self
    }

    func parse() {
        xmlParser.parse()
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?,
                attributes attributeDict: [String: String] = [:]) {
        if elementName == "Relationship",
           let id = attributeDict["Id"],
           let target = attributeDict["Target"] {
            relationships[id] = target
        }
    }
}

// MARK: - FileManager ZIP Extension

extension FileManager {
    /// Unzip a file to a destination directory using the `unzip` command.
    func unzipItem(at sourceURL: URL, to destinationURL: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-o", "-q", sourceURL.path, "-d", destinationURL.path]

        let errorPipe = Pipe()
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let errorMessage = String(data: errorData, encoding: .utf8) ?? "Unknown error"
            throw PPTXParseError.invalidFile("ZIP extraction failed: \(errorMessage)")
        }
    }
}
