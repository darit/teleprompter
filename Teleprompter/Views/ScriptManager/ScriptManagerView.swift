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
        // Defer to escape the current CA commit transaction — NSOpenPanel.runModal()
        // opens a new transaction which crashes if called mid-commit.
        DispatchQueue.main.async { self.performImportPPTX() }
    }

    private func performImportPPTX() {
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
            try? modelContext.save()
            selectedScript = script

            // Defer assistant + preview work to escape the current CA commit.
            let slides = result.slides
            let pptxURL = url
            Task { @MainActor in
                // Yield to let SwiftUI / CA finish the current transaction
                await Task.yield()

                // Generate previews BEFORE opening assistant so thumbnails are ready
                await generateSlidePreviews(for: script, slides: slides, pptxURL: pptxURL)

                let snapshots = script.sections.map { $0.toSnapshot() }
                assistantData = AssistantData(script: script, slides: slides, initialSnapshots: snapshots)
            }

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
        // Defer to escape the current CA commit transaction
        DispatchQueue.main.async { self.performUpdatePPTX(for: script) }
    }

    private func performUpdatePPTX(for script: Script) {
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
            try? modelContext.save()

            // Defer preview work to escape the current CA commit
            let slides = result.slides
            let pptxURL = url
            Task { @MainActor in
                await Task.yield()
                generateSlidePreviews(for: script, slides: slides, pptxURL: pptxURL)
            }

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
        let snapshots = script.sections.map { $0.toSnapshot() }
        assistantData = AssistantData(script: script, slides: slides, initialSnapshots: snapshots)
    }

    /// Generate and persist slide preview images, then save to model context.
    @MainActor
    private func generateSlidePreviews(for script: Script, slides: [SlideContent], pptxURL: URL) async {
        let ctx = modelContext
        let sectionIndex = Dictionary(script.sections.map { ($0.slideNumber, $0) }, uniquingKeysWith: { a, _ in a })

        // Try LibreOffice in background if available, otherwise card-render immediately
        if SlideRenderer.isAvailable {
            let renders = await Task.detached {
                (try? await SlideRenderer.renderSlides(pptxURL: pptxURL)) ?? []
            }.value
            let renderIndex = Dictionary(renders.map { ($0.slideNumber, $0.data) }, uniquingKeysWith: { a, _ in a })

            for slide in slides {
                guard let section = sectionIndex[slide.slideNumber] else { continue }
                let imageData = renderIndex[slide.slideNumber] ?? SlideCardRenderer.render(slide: slide)
                if let imageData {
                    let paths = SlideImageStore.save(images: [imageData], scriptId: script.storageId, slideNumber: slide.slideNumber, type: .preview)
                    section.thumbnailRelativePath = paths.first
                }
                if !slide.images.isEmpty {
                    SlideImageStore.saveRaw(images: slide.images, scriptId: script.storageId, slideNumber: slide.slideNumber)
                }
            }
            try? ctx.save()
        } else {
            // No LibreOffice — render cards synchronously on main actor (fast)
            for slide in slides {
                guard let section = sectionIndex[slide.slideNumber] else { continue }
                if let cardData = SlideCardRenderer.render(slide: slide) {
                    let paths = SlideImageStore.save(images: [cardData], scriptId: script.storageId, slideNumber: slide.slideNumber, type: .preview)
                    section.thumbnailRelativePath = paths.first
                }
                if !slide.images.isEmpty {
                    SlideImageStore.saveRaw(images: slide.images, scriptId: script.storageId, slideNumber: slide.slideNumber)
                }
            }
            try? ctx.save()
        }
    }

    private func openAssistantWindow(data: AssistantData) {
        let ctx = modelContext
        // Escape the current CA commit transaction before creating a window.
        Task { @MainActor in
            await Task.yield()
            AssistantWindowController.shared.show(
                script: data.script,
                slides: data.slides,
                initialSnapshots: data.initialSnapshots,
                modelContext: ctx
            )
        }
    }
}

// MARK: - Assistant Window Controller

/// Manages the Script Assistant window lifecycle outside of SwiftUI @State
/// to avoid dangling pointer crashes on close.
@MainActor
final class AssistantWindowController: NSObject, NSWindowDelegate {
    static let shared = AssistantWindowController()

    /// Strong reference keeps the window alive; set to nil on close.
    private var windowController: NSWindowController?

    func show(script: Script, slides: [SlideContent], initialSnapshots: [SectionSnapshot], modelContext: ModelContext) {
        // Close existing window cleanly
        if let existing = windowController {
            existing.window?.delegate = nil
            existing.close()
            windowController = nil
        }

        let contentView = ScriptAssistantView(
            script: script,
            slides: slides,
            initialSnapshots: initialSnapshots
        )
        .environment(\.modelContext, modelContext)

        let hostingView = NSHostingView(rootView: contentView)
        hostingView.autoresizingMask = [.width, .height]

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1200, height: 780),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Script Assistant"
        window.isRestorable = false
        window.contentView = hostingView
        window.minSize = NSSize(width: 900, height: 600)
        window.center()
        window.delegate = self

        let wc = NSWindowController(window: window)
        windowController = wc
        wc.showWindow(nil)
    }

    func windowWillClose(_ notification: Notification) {
        // Let AppKit finish closing naturally — just release our strong reference
        // on the next run loop turn so the window teardown completes first.
        DispatchQueue.main.async { [weak self] in
            self?.windowController = nil
        }
    }
}

#Preview {
    ScriptManagerView()
        .modelContainer(PreviewSampleData.container)
}
