// Teleprompter/Services/ScriptBackupManager.swift
import Foundation
import CryptoKit
import os.log

enum ScriptBackupManager {
    static let backupDirectory: URL = {
        let backupDir = PersistenceManager.appSupportDirectory
            .appendingPathComponent("Backups", isDirectory: true)
        try? FileManager.default.createDirectory(at: backupDir, withIntermediateDirectories: true)
        return backupDir
    }()

    private static let backupQueue = DispatchQueue(label: "com.darit.Teleprompter.backup", qos: .utility)

    /// Export a script and all its sections + chat history to a JSON file.
    /// Runs on a background queue to avoid blocking the main thread.
    @MainActor
    static func backup(script: Script) {
        // Capture all values on the main thread (SwiftData models aren't Sendable)
        let payload = ScriptBackup(
            name: script.name,
            createdAt: script.createdAt,
            modifiedAt: script.modifiedAt,
            scrollSpeed: script.scrollSpeed,
            fontSize: script.fontSize,
            targetDuration: script.targetDuration,
            sections: script.sortedSections.map { section in
                SectionBackup(
                    slideNumber: section.slideNumber,
                    label: section.label,
                    content: section.content,
                    order: section.order,
                    accentColorHex: section.accentColorHex,
                    isAIRefined: section.isAIRefined,
                    originalBodyText: section.originalBodyText,
                    originalNotes: section.originalNotes
                )
            },
            chatHistory: script.chatHistory.sorted { $0.order < $1.order }.map { msg in
                ChatMessageBackup(role: msg.role, content: msg.content, order: msg.order)
            }
        )

        let fileURL = backupFileURL(for: script.name)

        // Write on background queue
        backupQueue.async {
            do {
                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .iso8601
                encoder.outputFormatting = .prettyPrinted
                let data = try encoder.encode(payload)
                try data.write(to: fileURL, options: .atomic)
            } catch {
                Logger(subsystem: "com.darit.Teleprompter", category: "ScriptBackupManager")
                    .error("Backup failed for '\(payload.name)': \(error.localizedDescription)")
            }
        }
    }

    /// Deterministic file URL for a given script name (stable across app launches).
    private static func backupFileURL(for name: String) -> URL {
        let sanitizedName = name
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        let nameData = Data(name.utf8)
        let hash = Insecure.MD5.hash(data: nameData)
        let idHash = hash.prefix(4).map { String(format: "%02x", $0) }.joined()
        return backupDirectory.appendingPathComponent("\(sanitizedName)-\(idHash).json")
    }

    /// List all backup files sorted by modification date (newest first).
    static func listBackups() -> [URL] {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: backupDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: .skipsHiddenFiles
        ) else { return [] }

        return contents
            .filter { $0.pathExtension == "json" }
            .sorted { a, b in
                let dateA = (try? a.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let dateB = (try? b.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return dateA > dateB
            }
    }

    /// Restore a script from a backup JSON file.
    static func restore(from url: URL) throws -> ScriptBackup {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(ScriptBackup.self, from: data)
    }
}

// MARK: - Backup Models

struct ScriptBackup: Codable {
    let name: String
    let createdAt: Date
    let modifiedAt: Date
    let scrollSpeed: Double
    let fontSize: Double
    let targetDuration: Double?
    let sections: [SectionBackup]
    let chatHistory: [ChatMessageBackup]
}

struct SectionBackup: Codable {
    let slideNumber: Int
    let label: String
    let content: String
    let order: Int
    let accentColorHex: String
    let isAIRefined: Bool
    let originalBodyText: String
    let originalNotes: String
}

struct ChatMessageBackup: Codable {
    let role: String
    let content: String
    let order: Int
}

// MARK: - Notification

extension Notification.Name {
    static let scriptSectionEdited = Notification.Name("scriptSectionEdited")
}
