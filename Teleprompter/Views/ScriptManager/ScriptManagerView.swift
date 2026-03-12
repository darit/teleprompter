// Teleprompter/Views/ScriptManager/ScriptManagerView.swift
import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct ScriptManagerView: View {
    @State private var selectedScript: Script?
    @State private var showingAssistant = false
    @State private var assistantScript: Script?
    @State private var assistantSlides: [SlideContent] = []
    @State private var importError: String?
    @State private var showingImportError = false
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        NavigationSplitView {
            ScriptSidebarView(
                selectedScript: $selectedScript,
                onImport: { importPPTX() }
            )
            .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 280)
        } detail: {
            if let script = selectedScript {
                ScriptDetailView(
                    script: script,
                    onRefineWithAI: { openAssistant(for: script) }
                )
            } else {
                ContentUnavailableView(
                    "No Script Selected",
                    systemImage: "doc.text.magnifyingglass",
                    description: Text("Select a script from the sidebar or create a new one.")
                )
            }
        }
        .frame(minWidth: 700, minHeight: 450)
        .sheet(isPresented: $showingAssistant) {
            if let script = assistantScript {
                ScriptAssistantView(script: script, slides: assistantSlides)
                    .frame(minWidth: 800, minHeight: 600)
            }
        }
        .alert("Import Error", isPresented: $showingImportError) {
            Button("OK") {}
        } message: {
            Text(importError ?? "Unknown error")
        }
    }

    private func importPPTX() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.init(filenameExtension: "pptx")!]
        panel.allowsMultipleSelection = false
        panel.message = "Select a PowerPoint presentation to import"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let result = try PPTXParser.parse(fileAt: url)

            let script = Script(name: result.fileName)
            let accentColors = ["#4A9EFF", "#34C759", "#FF9500", "#FF2D55", "#AF52DE", "#5AC8FA", "#FFCC00", "#FF6B35"]

            for slide in result.slides {
                let section = ScriptSection(
                    slideNumber: slide.slideNumber,
                    label: slide.title.isEmpty ? "Slide \(slide.slideNumber)" : slide.title,
                    content: slide.notes.isEmpty ? "" : slide.notes,
                    order: slide.slideNumber - 1,
                    accentColorHex: accentColors[(slide.slideNumber - 1) % accentColors.count]
                )
                script.sections.append(section)
            }

            modelContext.insert(script)
            selectedScript = script

            // Open assistant with slides
            assistantSlides = result.slides
            assistantScript = script
            showingAssistant = true

            if !result.warnings.isEmpty {
                importError = "Imported with warnings:\n" + result.warnings.joined(separator: "\n")
                showingImportError = true
            }
        } catch {
            importError = error.localizedDescription
            showingImportError = true
        }
    }

    private func openAssistant(for script: Script) {
        // Build SlideContent from existing sections
        assistantSlides = script.sortedSections.map { section in
            SlideContent(
                slideNumber: section.slideNumber,
                title: section.label,
                bodyText: section.content,
                notes: ""
            )
        }
        assistantScript = script
        showingAssistant = true
    }
}

#Preview {
    ScriptManagerView()
        .modelContainer(PreviewSampleData.container)
}
