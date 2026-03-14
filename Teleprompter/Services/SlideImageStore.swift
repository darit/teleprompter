// Teleprompter/Services/SlideImageStore.swift
import Foundation
import AppKit

enum SlideImageStore {
    enum ImageType: String {
        case preview   // Content card or LibreOffice render (shown in UI)
        case media     // Extracted media from PPTX (for LLM vision context)
    }

    static let baseDirectory: URL = {
        let dir = PersistenceManager.appSupportDirectory
            .appendingPathComponent("SlideImages", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    /// Save preview images for a slide (thumbnailed to 480px). Returns relative paths.
    @discardableResult
    static func save(images: [Data], scriptId: String, slideNumber: Int, type: ImageType) -> [String] {
        let typeDir = directoryFor(scriptId: scriptId, type: type)

        var paths: [String] = []
        for (index, imageData) in images.enumerated() {
            let filename = "slide-\(slideNumber)-\(index).jpg"
            let fileURL = typeDir.appendingPathComponent(filename)

            if let thumbnail = createThumbnail(from: imageData, maxWidth: 480) {
                do {
                    try thumbnail.write(to: fileURL, options: .atomic)
                    paths.append("\(scriptId)/\(type.rawValue)/\(filename)")
                } catch {
                    print("SlideImageStore: failed to write \(filename): \(error)")
                }
            }
        }
        return paths
    }

    /// Save extracted media images at original quality (for LLM vision context).
    static func saveRaw(images: [Data], scriptId: String, slideNumber: Int) {
        let typeDir = directoryFor(scriptId: scriptId, type: .media)

        for (index, imageData) in images.enumerated() {
            let filename = "slide-\(slideNumber)-\(index).dat"
            let fileURL = typeDir.appendingPathComponent(filename)
            try? imageData.write(to: fileURL, options: .atomic)
        }
    }

    private static func directoryFor(scriptId: String, type: ImageType) -> URL {
        let typeDir = baseDirectory
            .appendingPathComponent(scriptId, isDirectory: true)
            .appendingPathComponent(type.rawValue, isDirectory: true)
        try? FileManager.default.createDirectory(at: typeDir, withIntermediateDirectories: true)
        return typeDir
    }

    /// Load a thumbnail image. Async to avoid main-thread I/O.
    static func load(relativePath: String) async -> NSImage? {
        let url = baseDirectory.appendingPathComponent(relativePath)
        return await Task.detached {
            NSImage(contentsOf: url)
        }.value
    }

    /// Delete all images for a script.
    static func delete(scriptId: String) {
        let scriptDir = baseDirectory.appendingPathComponent(scriptId)
        try? FileManager.default.removeItem(at: scriptDir)
    }

    private static func createThumbnail(from data: Data, maxWidth: CGFloat) -> Data? {
        guard let image = NSImage(data: data) else { return nil }
        let size = image.size
        guard size.width > 0 else { return nil }

        let scale = min(maxWidth / size.width, 1.0)
        if scale >= 1.0 {
            guard let tiffData = image.tiffRepresentation,
                  let bitmap = NSBitmapImageRep(data: tiffData),
                  let jpegData = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.8])
            else { return nil }
            return jpegData
        }

        let newSize = NSSize(width: size.width * scale, height: size.height * scale)
        let newImage = NSImage(size: newSize, flipped: false) { rect in
            image.draw(in: rect)
            return true
        }

        guard let tiffData = newImage.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let jpegData = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.8])
        else { return nil }

        return jpegData
    }
}
