// Teleprompter/Services/SlideRenderer.swift
import Foundation

enum SlideRenderer {
    private static let searchPaths = [
        "/Applications/LibreOffice.app/Contents/MacOS/soffice",
        "/usr/local/bin/soffice",
        "/opt/homebrew/bin/soffice",
    ]

    static var isAvailable: Bool {
        resolvedPath() != nil
    }

    private static func resolvedPath() -> String? {
        searchPaths.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// Render all slides in a PPTX to PNG via LibreOffice headless.
    /// Returns empty array if LibreOffice is not installed.
    static func renderSlides(pptxURL: URL) async throws -> [(slideNumber: Int, data: Data)] {
        guard let sofficePath = resolvedPath() else { return [] }

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("teleprompter-render-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: sofficePath)
        process.arguments = [
            "--headless",
            "--convert-to", "png",
            "--outdir", tempDir.path,
            pptxURL.path
        ]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        // Use terminationHandler to avoid blocking the cooperative thread pool
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            process.terminationHandler = { _ in
                continuation.resume()
            }
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }

        defer { try? FileManager.default.removeItem(at: tempDir) }

        guard process.terminationStatus == 0 else { return [] }

        let files = try FileManager.default.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "png" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        return try files.enumerated().map { (index, file) in
            (index + 1, try Data(contentsOf: file))
        }
    }
}
