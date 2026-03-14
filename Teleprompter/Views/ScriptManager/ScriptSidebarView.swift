// Teleprompter/Views/ScriptManager/ScriptSidebarView.swift
import SwiftUI
import SwiftData
import AppKit
import UniformTypeIdentifiers

struct ScriptSidebarView: View {
    @Query(sort: \Script.modifiedAt, order: .reverse) private var scripts: [Script]
    @Binding var selectedScript: Script?
    @Environment(\.modelContext) private var modelContext
    @State private var searchText = ""
    @State private var restoreError: String?
    @State private var showingRestoreError = false
    var onImport: () -> Void = {}

    private var filteredScripts: [Script] {
        if searchText.isEmpty { return scripts }
        return scripts.filter { script in
            script.name.localizedCaseInsensitiveContains(searchText)
            || script.sections.contains { section in
                section.label.localizedCaseInsensitiveContains(searchText)
                || section.content.localizedCaseInsensitiveContains(searchText)
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Action buttons
            HStack(spacing: 6) {
                Button("+ New") { createNewScript() }
                    .buttonStyle(.glass)

                Button("Import") { onImport() }
                    .buttonStyle(.glass)

                Button("Restore") { restoreFromBackup() }
                    .buttonStyle(.glass)
                    .help("Restore a script from a backup file")
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 8)

            // Script list
            List(filteredScripts, selection: $selectedScript) { script in
                ScriptRowView(script: script)
                    .tag(script)
                    .contextMenu {
                        Button("Delete", role: .destructive) {
                            deleteScript(script)
                        }
                    }
            }
            .searchable(text: $searchText, prompt: "Search scripts...")

            // Model status at bottom (model name wired in Plan 2)
            HStack(spacing: 6) {
                Circle()
                    .fill(.green)
                    .frame(width: 5, height: 5)
                Text("No model configured")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }
            .padding(10)
        }
        .alert("Restore Error", isPresented: $showingRestoreError) {
            Button("OK") {}
        } message: {
            Text(restoreError ?? "Unknown error")
        }
    }

    private func createNewScript() {
        let script = Script(name: "Untitled Script")
        modelContext.insert(script)
        selectedScript = script
    }

    private func deleteScript(_ script: Script) {
        if selectedScript == script {
            selectedScript = nil
        }
        SlideImageStore.delete(scriptId: script.storageId)
        modelContext.delete(script)
    }

    private func restoreFromBackup() {
        let panel = NSOpenPanel()
        panel.directoryURL = ScriptBackupManager.backupDirectory
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.message = "Select a backup file to restore"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let backup = try ScriptBackupManager.restore(from: url)
            let script = Script(
                name: backup.name,
                scrollSpeed: backup.scrollSpeed,
                fontSize: backup.fontSize,
                targetDuration: backup.targetDuration
            )

            for sectionBackup in backup.sections {
                let section = ScriptSection(
                    slideNumber: sectionBackup.slideNumber,
                    label: sectionBackup.label,
                    content: sectionBackup.content,
                    order: sectionBackup.order,
                    accentColorHex: sectionBackup.accentColorHex,
                    isAIRefined: sectionBackup.isAIRefined,
                    originalBodyText: sectionBackup.originalBodyText,
                    originalNotes: sectionBackup.originalNotes
                )
                script.sections.append(section)
            }

            for chatBackup in backup.chatHistory {
                let msg = PersistedChatMessage(
                    role: chatBackup.role,
                    content: chatBackup.content,
                    order: chatBackup.order
                )
                script.chatHistory.append(msg)
            }

            modelContext.insert(script)
            selectedScript = script
        } catch {
            restoreError = error.localizedDescription
            showingRestoreError = true
        }
    }
}

#Preview {
    ScriptSidebarView(selectedScript: .constant(nil), onImport: {})
        .modelContainer(PreviewSampleData.container)
        .frame(width: 220)
}
