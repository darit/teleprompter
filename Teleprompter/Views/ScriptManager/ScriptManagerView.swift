// Teleprompter/Views/ScriptManager/ScriptManagerView.swift
import SwiftUI
import SwiftData
import AppKit
import UniformTypeIdentifiers

struct ScriptManagerView: View {
    @State private var selectedScript: Script?
    @State private var assistantData: AssistantData?
    @State private var importError: String?
    @State private var showingImportError = false
    @State private var assistantWindow: NSWindow?
    @Environment(\.modelContext) private var modelContext

    struct AssistantData: Identifiable {
        let id = UUID()
        let script: Script
        let slides: [SlideContent]
        let initialSnapshots: [SectionSnapshot]
    }

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
                    onRefineWithAI: { openAssistant(for: script) },
                    onUpdatePPTX: { updatePPTX(for: script) },
                    onPresent: { launchTeleprompter(for: script) }
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
        .onChange(of: assistantData?.id) {
            guard let data = assistantData else { return }
            openAssistantWindow(data: data)
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
                    accentColorHex: accentColors[(slide.slideNumber - 1) % accentColors.count],
                    originalBodyText: slide.bodyText,
                    originalNotes: slide.notes
                )
                script.sections.append(section)
            }

            modelContext.insert(script)
            selectedScript = script

            // Open assistant with slides
            assistantData = AssistantData(script: script, slides: result.slides, initialSnapshots: [])

            if !result.warnings.isEmpty {
                importError = "Imported with warnings:\n" + result.warnings.joined(separator: "\n")
                showingImportError = true
            }
        } catch {
            importError = error.localizedDescription
            showingImportError = true
        }
    }

    private func launchTeleprompter(for script: Script) {
        guard !script.sections.isEmpty else { return }
        let state = TeleprompterState.from(script: script)
        TeleprompterWindowController.shared.show(state: state)
        GlobalShortcutManager.shared.start(state: state)
    }

    private func updatePPTX(for script: Script) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.init(filenameExtension: "pptx")!]
        panel.allowsMultipleSelection = false
        panel.message = "Select an updated PowerPoint presentation"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let result = try PPTXParser.parse(fileAt: url)
            let accentColors = ["#4A9EFF", "#34C759", "#FF9500", "#FF2D55", "#AF52DE", "#5AC8FA", "#FFCC00", "#FF6B35"]
            let existingSections = Dictionary(uniqueKeysWithValues: script.sections.map { ($0.slideNumber, $0) })

            for slide in result.slides {
                if let existing = existingSections[slide.slideNumber] {
                    // Update original PPTX content, keep generated script
                    existing.label = slide.title.isEmpty ? "Slide \(slide.slideNumber)" : slide.title
                    existing.originalBodyText = slide.bodyText
                    existing.originalNotes = slide.notes
                } else {
                    // New slide added to the presentation
                    let section = ScriptSection(
                        slideNumber: slide.slideNumber,
                        label: slide.title.isEmpty ? "Slide \(slide.slideNumber)" : slide.title,
                        content: "",
                        order: slide.slideNumber - 1,
                        accentColorHex: accentColors[(slide.slideNumber - 1) % accentColors.count],
                        originalBodyText: slide.bodyText,
                        originalNotes: slide.notes
                    )
                    script.sections.append(section)
                }
            }

            // Remove sections for slides that no longer exist
            let newSlideNumbers = Set(result.slides.map(\.slideNumber))
            let removedSections = script.sections.filter { !newSlideNumbers.contains($0.slideNumber) }
            for section in removedSections {
                modelContext.delete(section)
                script.sections.removeAll { $0 === section }
            }

            script.modifiedAt = .now

            if !result.warnings.isEmpty {
                importError = "Updated with warnings:\n" + result.warnings.joined(separator: "\n")
                showingImportError = true
            }
        } catch {
            importError = error.localizedDescription
            showingImportError = true
        }
    }

    private func openAssistant(for script: Script) {
        let slides = script.sortedSections.map { $0.toSlideContent() }
        let snapshots = script.sections.map { section in
            SectionSnapshot(
                slideNumber: section.slideNumber,
                label: section.label,
                content: section.content,
                accentColorHex: section.accentColorHex
            )
        }
        assistantData = AssistantData(script: script, slides: slides, initialSnapshots: snapshots)
    }

    private func openAssistantWindow(data: AssistantData) {
        // Close existing assistant window if any and let it finish tearing down
        if let existing = assistantWindow {
            existing.contentView = nil
            existing.close()
            assistantWindow = nil
        }

        // Delay creation to let the old view hierarchy finish cleanup
        DispatchQueue.main.async {
            let contentView = ScriptAssistantView(script: data.script, slides: data.slides, initialSnapshots: data.initialSnapshots)
                .environment(\.modelContext, modelContext)

            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 1200, height: 780),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = "Script Assistant"
            window.contentView = NSHostingView(rootView: contentView)
            window.minSize = NSSize(width: 900, height: 600)
            window.center()
            window.makeKeyAndOrderFront(nil)

            assistantWindow = window
        }
    }
}

#Preview {
    ScriptManagerView()
        .modelContainer(PreviewSampleData.container)
}
