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
        WindowGroup {
            ContentView() // will be replaced with ScriptManagerView in Task 11
        }
        .modelContainer(for: [Script.self, ScriptSection.self])
    }
}
