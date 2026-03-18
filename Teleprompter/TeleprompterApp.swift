//
//  TeleprompterApp.swift
//  Teleprompter
//
//  Created by Danny Rodriguez Guerrero on 12/03/26.
//

import SwiftUI
import SwiftData
import os.log

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
            Logger(subsystem: "com.darit.Teleprompter", category: "App")
                .error("Failed to create persistent store: \(error.localizedDescription). Falling back to in-memory.")
            let fallback = ModelConfiguration(isStoredInMemoryOnly: true)
            do {
                modelContainer = try ModelContainer(
                    for: Script.self, ScriptSection.self, PersistedChatMessage.self,
                    configurations: fallback
                )
            } catch {
                fatalError("Failed to create even in-memory ModelContainer: \(error)")
            }
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
