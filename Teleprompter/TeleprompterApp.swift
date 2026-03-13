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
    var body: some Scene {
        Window("Teleprompter", id: "main") {
            ScriptManagerView()
        }
        .modelContainer(for: [Script.self, ScriptSection.self, PersistedChatMessage.self])
        .commands {
            CommandGroup(after: .appSettings) {
                Button("Settings...") {
                    SettingsWindowController.shared.show()
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }

        Settings {
            SettingsView()
        }
    }
}

/// Manages a standalone settings window (fallback for programmatic opening).
final class SettingsWindowController {
    static let shared = SettingsWindowController()
    private init() {}

    func show() {
        // Use the standard Settings scene activation
        if #available(macOS 14.0, *) {
            NSApp.activate()
        }
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }
}
