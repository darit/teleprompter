// Teleprompter/Views/ScriptManager/ScriptSidebarView.swift
import SwiftUI
import SwiftData

struct ScriptSidebarView: View {
    @Query(sort: \Script.modifiedAt, order: .reverse) private var scripts: [Script]
    @Binding var selectedScript: Script?
    @Environment(\.modelContext) private var modelContext
    @State private var searchText = ""

    private var filteredScripts: [Script] {
        if searchText.isEmpty { return scripts }
        return scripts.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Action buttons
            HStack(spacing: 6) {
                Button("+ New") { createNewScript() }
                    .buttonStyle(.glass)

                Button("Import") { /* Plan 2: PPTX import */ }
                    .buttonStyle(.glass)
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
        modelContext.delete(script)
    }
}

#Preview {
    ScriptSidebarView(selectedScript: .constant(nil))
        .modelContainer(PreviewSampleData.container)
        .frame(width: 220)
}
