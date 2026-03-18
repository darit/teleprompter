// Teleprompter/Services/PersistenceManager.swift
import Foundation
import SwiftData

enum PersistenceManager {
    /// Stable database location that survives Xcode rebuilds.
    /// ~/Library/Application Support/com.darit.Teleprompter/
    static let appSupportDirectory: URL = {
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            fatalError("Application Support directory not found")
        }
        let appDir = appSupport.appendingPathComponent("com.darit.Teleprompter", isDirectory: true)
        try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        return appDir
    }()

    static let storeURL: URL = appSupportDirectory.appendingPathComponent("Teleprompter.sqlite")

    /// Migrate the old default SwiftData store to the new stable location.
    /// The old store lives at ~/Library/Application Support/default.store (non-sandboxed).
    static func migrateOldStoreIfNeeded() {
        guard let oldStoreBase = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return }
        let oldStore = oldStoreBase.appendingPathComponent("default.store")
        guard FileManager.default.fileExists(atPath: oldStore.path),
              !FileManager.default.fileExists(atPath: storeURL.path) else { return }
        try? FileManager.default.copyItem(at: oldStore, to: storeURL)
    }
}
