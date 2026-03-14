//
//  TeleprompterApp.swift
//  Teleprompter
//
//  Created by Danny Rodriguez Guerrero on 12/03/26.
//

import SwiftUI
import SwiftData

@main
struct TeleprompterApp: App {
    let modelContainer: ModelContainer

    init() {
        PersistenceManager.migrateOldStoreIfNeeded()

        let config = ModelConfiguration(url: PersistenceManager.storeURL)
        do {
            modelContainer = try ModelContainer(
                for: Script.self, ScriptSection.self, PersistedChatMessage.self,
                configurations: config
            )
        } catch {
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

        Settings {
            SettingsView()
        }
    }
}
