// Teleprompter/PPTX/SlideContent.swift
import Foundation

struct SlideContent: Identifiable, Sendable {
    let id = UUID()
    let slideNumber: Int
    let title: String
    let bodyText: String
    let notes: String
    /// Images extracted from this slide (PNG/JPEG data)
    let images: [Data]

    var isEmpty: Bool {
        title.isEmpty && bodyText.isEmpty
    }

    var summary: String {
        if !title.isEmpty {
            return "Slide \(slideNumber): \(title)"
        }
        let preview = String(bodyText.prefix(60))
        return "Slide \(slideNumber): \(preview)..."
    }
}

struct PPTXParseResult: Sendable {
    let fileName: String
    let slides: [SlideContent]
    let warnings: [String]
}

enum PPTXParseError: LocalizedError {
    case invalidFile(String)
    case encrypted
    case noSlidesFound

    var errorDescription: String? {
        switch self {
        case .invalidFile(let detail): return "This file could not be read as a PowerPoint presentation: \(detail)"
        case .encrypted: return "This file is password-protected and cannot be imported."
        case .noSlidesFound: return "No slides were found in this presentation."
        }
    }
}
