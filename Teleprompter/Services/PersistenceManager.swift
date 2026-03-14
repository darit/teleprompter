// Teleprompter/Services/PersistenceManager.swift
import Foundation
import SwiftData

enum PersistenceManager {
    /// Stable database location that survives Xcode rebuilds.
    /// ~/Library/Application Support/com.dannyrodriguez.Teleprompter/
    static let appSupportDirectory: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = appSupport.appendingPathComponent("com.dannyrodriguez.Teleprompter", isDirectory: true)
        try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        return appDir
    }()

    static let storeURL: URL = appSupportDirectory.appendingPathComponent("Teleprompter.sqlite")

    /// Migrate the old default SwiftData store to the new stable location.
    /// The old store lives at ~/Library/Application Support/default.store (non-sandboxed).
    static func migrateOldStoreIfNeeded() {
        let oldStore = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("default.store")
        guard FileManager.default.fileExists(atPath: oldStore.path),
              !FileManager.default.fileExists(atPath: storeURL.path) else { return }
        try? FileManager.default.copyItem(at: oldStore, to: storeURL)
    }
}
