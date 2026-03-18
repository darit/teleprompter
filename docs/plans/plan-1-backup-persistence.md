# Plan 1: Backup & Data Persistence

**Priority:** 1 (do first)
**Estimated effort:** 1-2 sessions
**Risk:** Low

## Problem

The SwiftData store lives inside the Xcode-managed app container. Every clean build / "Delete Derived Data" wipes all scripts, chat history, and generated speeches. UserDefaults (AppSettings) also resets.

## Goal

Scripts survive app rebuilds, Xcode clean builds, and app reinstalls. Users never lose generated speeches.

---

## Step 1: Move SwiftData store to a stable location

**File to modify:** `Teleprompter/TeleprompterApp.swift`

Currently the `.modelContainer(for:)` modifier uses the default location (inside the app sandbox container, which Xcode wipes on rebuild). Move it to a stable, user-visible path.

**Important:** The `.modelContainer(for:configurations:)` SwiftUI modifier does NOT exist. You must create the `ModelContainer` manually and handle the throwing init with a fallback:

```swift
@main
struct TeleprompterApp: App {
    let modelContainer: ModelContainer

    init() {
        let config = ModelConfiguration(url: PersistenceManager.storeURL)
        do {
            modelContainer = try ModelContainer(
                for: Script.self, ScriptSection.self, PersistedChatMessage.self,
                configurations: config
            )
        } catch {
            // Fallback to in-memory store so the app still launches
            print("Failed to create persistent store: \(error). Falling back to in-memory.")
            let fallback = ModelConfiguration(isStoredInMemoryOnly: true)
            modelContainer = try! ModelContainer(
                for: Script.self, ScriptSection.self, PersistedChatMessage.self,
                configurations: fallback
            )
        }
    }

    var body: some Scene {
        Window("Teleprompter", id: "main") {
            ScriptManagerView()
        }
        .modelContainer(modelContainer)
        // ... rest unchanged
    }
}
```

**New file:** `Teleprompter/Services/PersistenceManager.swift`

```swift
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
}
```

**Why `~/Library/Application Support/`:** It's the standard macOS location for persistent app data. Xcode never touches it. It survives reinstalls. It's backed up by Time Machine.

**Note:** Use `.sqlite` extension (not `.store`) — SwiftData's underlying SQLite store expects this convention.

### Migration from old store

The old default store lives at `~/Library/Application Support/default.store` (non-sandboxed app). On first launch with the new location:

```swift
// In PersistenceManager:
static func migrateOldStoreIfNeeded() {
    let oldStore = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        .appendingPathComponent("default.store")
    guard FileManager.default.fileExists(atPath: oldStore.path),
          !FileManager.default.fileExists(atPath: storeURL.path) else { return }
    try? FileManager.default.copyItem(at: oldStore, to: storeURL)
}
```

Call this in `TeleprompterApp.init()` before creating the `ModelContainer`.

---

## Step 2: Move AppSettings to a stable UserDefaults suite

**File to modify:** `Teleprompter/Services/AppSettings.swift`

Replace every `UserDefaults.standard` with a suite-scoped UserDefaults that won't be affected by sandbox resets:

```swift
@Observable
final class AppSettings {
    static let shared = AppSettings()

    private let defaults = UserDefaults(suiteName: "com.dannyrodriguez.Teleprompter")!

    init() {
        migrateFromStandardIfNeeded()
    }

    var showNextSlideBanner: Bool {
        get { defaults.object(forKey: "showNextSlideBanner") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "showNextSlideBanner") }
    }
    // ... repeat for all 12 properties, changing UserDefaults.standard -> defaults
}
```

**Why:** `UserDefaults.standard` is scoped to the app's sandbox container. A `suiteName` UserDefaults is stored in `~/Library/Preferences/com.dannyrodriguez.Teleprompter.plist`, which survives rebuilds. (Note: this only works for non-sandboxed apps. If we ever sandbox for the App Store, we'll need a different approach.)

### One-time migration from UserDefaults.standard

Without this, users lose all their settings on first launch after the change:

```swift
private func migrateFromStandardIfNeeded() {
    let migrationKey = "didMigrateToSuiteDefaults"
    guard !defaults.bool(forKey: migrationKey) else { return }

    let standard = UserDefaults.standard
    let keysToMigrate = [
        "showNextSlideBanner", "transitionDwellSeconds", "showPlayCountdown",
        "playCountdownSeconds", "showSectionTimer", "showStageDirections",
        "autoAdvance", "alwaysOnTop", "defaultProvider", "maxParallelSlides",
        "lmStudioBaseURL", "speechTone"
    ]
    for key in keysToMigrate {
        if let value = standard.object(forKey: key) {
            defaults.set(value, forKey: key)
        }
    }
    defaults.set(true, forKey: migrationKey)
}
```

---

## Step 3: Auto-backup scripts to a stable location

**New file:** `Teleprompter/Services/ScriptBackupManager.swift`

Automatically export scripts as JSON whenever they're saved. Uses the App Support directory (not ~/Documents) to avoid iCloud Drive sync churn:

```swift
import Foundation

enum ScriptBackupManager {
    static let backupDirectory: URL = {
        let backupDir = PersistenceManager.appSupportDirectory
            .appendingPathComponent("Backups", isDirectory: true)
        try? FileManager.default.createDirectory(at: backupDir, withIntermediateDirectories: true)
        return backupDir
    }()

    /// Export a script and all its sections + chat history to a JSON file.
    /// Debounced: call freely, writes are coalesced via atomic overwrite.
    static func backup(script: Script) {
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

        // Use script name + truncated UUID to avoid filename collisions
        let sanitizedName = script.name
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        // Use persistentModelID hash for uniqueness
        let idHash = String(script.name.hashValue, radix: 16, uppercase: false)
        let fileURL = backupDirectory.appendingPathComponent("\(sanitizedName)-\(idHash).json")

        do {
            let data = try JSONEncoder().encode(payload)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            print("Backup failed for '\(script.name)': \(error)")
        }
    }

    /// Restore a script from a backup JSON file.
    static func restore(from url: URL) throws -> ScriptBackup {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(ScriptBackup.self, from: data)
    }
}

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
```

### Where to trigger backups

**File to modify:** `Teleprompter/Services/ConversationManager.swift`

Debounce backups — don't write on every slide during `generateAllSlides`. Instead, backup once after all work completes:

```swift
// In generateAllSlides(), after the summary assistant message is built (around line 256):
ScriptBackupManager.backup(script: script)

// In streamResponse(), after final parse (around line 319):
ScriptBackupManager.backup(script: script)
```

**File to modify:** `Teleprompter/Views/ScriptManager/SlideSectionView.swift`

For manual edits, post a notification that the parent view can observe:

```swift
private func commitEdit() {
    isEditing = false
    editorFocused = false
    NotificationCenter.default.post(name: .scriptSectionEdited, object: nil)
}
```

**File to modify:** `Teleprompter/Views/ScriptManager/ScriptDetailView.swift` (or wherever the script is accessible)

```swift
.onReceive(NotificationCenter.default.publisher(for: .scriptSectionEdited)) { _ in
    ScriptBackupManager.backup(script: script)
}
```

Add the notification name:
```swift
extension Notification.Name {
    static let scriptSectionEdited = Notification.Name("scriptSectionEdited")
}
```

---

## Step 4: Add restore-from-backup UI

**File to modify:** `Teleprompter/Views/ScriptManager/ScriptSidebarView.swift`

Add a menu item or button: "Restore from Backup..."

Opens an NSOpenPanel pointed at `~/Library/Application Support/com.dannyrodriguez.Teleprompter/Backups/`, filters for `.json` files, decodes the `ScriptBackup`, creates a new `Script` + `ScriptSection` + `PersistedChatMessage` objects, and inserts into the model context.

---

## Files summary

| Action | File |
|--------|------|
| **Create** | `Teleprompter/Services/PersistenceManager.swift` |
| **Create** | `Teleprompter/Services/ScriptBackupManager.swift` |
| **Modify** | `Teleprompter/TeleprompterApp.swift` — manual ModelContainer init with fallback |
| **Modify** | `Teleprompter/Services/AppSettings.swift` — suite UserDefaults + migration |
| **Modify** | `Teleprompter/Services/ConversationManager.swift` — trigger backup after completion |
| **Modify** | `Teleprompter/Views/ScriptManager/SlideSectionView.swift` — post notification on edit |
| **Modify** | `Teleprompter/Views/ScriptManager/ScriptSidebarView.swift` — restore UI |

## Verification

1. Build and run. Create a script, generate speeches.
2. Clean build (Cmd+Shift+K) or delete derived data.
3. Build and run again. Scripts should still be there.
4. Check `~/Library/Application Support/com.dannyrodriguez.Teleprompter/Backups/` — JSON files should exist with chat history.
5. Delete the app's data. Use "Restore from Backup" — scripts + chat history should come back.
6. Verify settings survive a clean build (suite UserDefaults migration).

## Future considerations

- **SwiftData schema versioning:** If we later change `@Model` schemas, we'll need `VersionedSchema` and `SchemaMigrationPlan`. Not needed now since this is the first stable store.
- **App Store sandboxing:** Suite UserDefaults and Application Support paths work for non-sandboxed apps. If we sandbox for the App Store, both need to move into the app container (which Xcode won't wipe in production, only during development).
