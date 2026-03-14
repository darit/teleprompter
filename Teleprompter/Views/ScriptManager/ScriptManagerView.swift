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

            // Open assistant immediately (previews populate async)
            let snapshots = script.sections.map { $0.toSnapshot() }
            assistantData = AssistantData(script: script, slides: result.slides, initialSnapshots: snapshots)

            // Generate slide previews in background
            generateSlidePreviews(for: script, slides: result.slides, pptxURL: url)

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

            // Re-render slide previews in background
            generateSlidePreviews(for: script, slides: result.slides, pptxURL: url)

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
    /// Runs off the main actor for LibreOffice/disk I/O, returns to main for SwiftData + card rendering.
    private func generateSlidePreviews(for script: Script, slides: [SlideContent], pptxURL: URL) {
        let ctx = modelContext
        Task {
            // LibreOffice rendering off main thread
            let libreOfficeRenders = await Task.detached {
                (try? await SlideRenderer.renderSlides(pptxURL: pptxURL)) ?? []
            }.value

            let renderIndex = Dictionary(libreOfficeRenders.map { ($0.slideNumber, $0.data) }, uniquingKeysWith: { a, _ in a })
            let sectionIndex = Dictionary(script.sections.map { ($0.slideNumber, $0) }, uniquingKeysWith: { a, _ in a })

            // Card rendering + disk I/O on main (ImageRenderer requires MainActor)
            await MainActor.run {
                for slide in slides {
                    guard let section = sectionIndex[slide.slideNumber] else { continue }

                    if let rendered = renderIndex[slide.slideNumber] {
                        let paths = SlideImageStore.save(
                            images: [rendered],
                            scriptId: script.storageId,
                            slideNumber: slide.slideNumber,
                            type: .preview
                        )
                        section.thumbnailRelativePath = paths.first ?? ""
                    } else if let cardData = SlideCardRenderer.render(slide: slide) {
                        let paths = SlideImageStore.save(
                            images: [cardData],
                            scriptId: script.storageId,
                            slideNumber: slide.slideNumber,
                            type: .preview
                        )
                        section.thumbnailRelativePath = paths.first ?? ""
                    }

                    if !slide.images.isEmpty {
                        SlideImageStore.saveRaw(
                            images: slide.images,
                            scriptId: script.storageId,
                            slideNumber: slide.slideNumber
                        )
                    }
                }

                try? ctx.save()
            }
        }
    }

    private func openAssistantWindow(data: AssistantData) {
        // Capture everything we need before escaping the SwiftUI render cycle.
        // Any @State mutation during body evaluation / CA commit causes
        // "Invalid attempt to open a new transaction during CA commit" crashes.
        let ctx = modelContext

        // Use Task to fully escape the current SwiftUI / CoreAnimation commit.
        // DispatchQueue.main.async alone is not sufficient — it can still land
        // inside the same CA transaction boundary.
        Task { @MainActor in
            // Tear down previous window if any
            if let existing = assistantWindow {
                existing.orderOut(nil)
                existing.contentView = nil
                existing.close()
                assistantWindow = nil
            }

            // Yield once more to let AppKit finish any pending cleanup
            await Task.yield()

            let contentView = ScriptAssistantView(
                script: data.script,
                slides: data.slides,
                initialSnapshots: data.initialSnapshots
            )
            .environment(\.modelContext, ctx)

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

            // Clean up our reference when the user closes the window to prevent
            // use-after-free on the hosting view's backing objects.
            let delegate = AssistantWindowDelegate {}
            window.delegate = delegate
            // Keep the delegate alive as long as the window exists.
            objc_setAssociatedObject(window, AssistantWindowDelegate.key, delegate, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)

            window.makeKeyAndOrderFront(nil)
            assistantWindow = window
        }
    }
}

// MARK: - Assistant Window Delegate

/// Releases the assistant window reference on close so the hosting view
/// and its SwiftUI content are torn down cleanly before macOS attempts
/// window restoration (which would otherwise crash with className=(null)).
private final class AssistantWindowDelegate: NSObject, NSWindowDelegate {
    static let key = UnsafeRawPointer(bitPattern: "AssistantWindowDelegate".hashValue)!
    private let onClose: () -> Void

    init(onClose: @escaping () -> Void) {
        self.onClose = onClose
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        window.contentView = nil
        onClose()
    }
}

#Preview {
    ScriptManagerView()
        .modelContainer(PreviewSampleData.container)
}
