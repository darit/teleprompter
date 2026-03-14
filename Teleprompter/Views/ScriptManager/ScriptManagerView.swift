// Teleprompter/Views/ScriptManager/ScriptManagerView.swift
import SwiftUI
import SwiftData
import AppKit
import UniformTypeIdentifiers

struct ScriptManagerView: View {
    @State private var selectedScript: Script?
    @State private var showAssistant = false
    @State private var conversation: ConversationManager?
    @State private var selectedProvider: ProviderChoice = .foundationModel
    @State private var selectedTone: SpeechTone = .conversational
    @State private var targetMinutes: Int = 10
    @State private var isLoadingProvider = false
    @State private var providerError: String?
    @State private var showingProviderError = false
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
                HStack(spacing: 0) {
                    ScriptDetailView(
                        script: script,
                        isAssistantOpen: showAssistant,
                        generatingSlides: conversation?.parallelGeneratingSlides ?? [],
                        onRefineWithAI: { toggleAssistant(for: script) },
                        onUpdatePPTX: { updatePPTX(for: script) },
                        onPresent: { launchTeleprompter(for: script) },
                        onGenerateSlide: { slideNumber in
                            if !showAssistant {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    showAssistant = true
                                }
                            }
                            Task {
                                if conversation == nil {
                                    await initializeConversation(for: script)
                                }
                                await conversation?.generateSlide(slideNumber)
                            }
                        }
                    )

                    if showAssistant {
                        Rectangle()
                            .fill(Color(nsColor: .separatorColor))
                            .frame(width: 1)

                        if let conversation {
                            AssistantPanelView(
                                conversation: conversation,
                                selectedProvider: $selectedProvider,
                                selectedTone: $selectedTone,
                                targetMinutes: $targetMinutes,
                                onClose: {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        showAssistant = false
                                }
                            },
                            onSwitchProvider: { switchProvider() }
                        )
                        .frame(width: 380)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                        } else {
                            VStack {
                                Spacer()
                                ProgressView("Connecting to \(selectedProvider.rawValue)...")
                                    .font(.system(size: 12))
                                Spacer()
                            }
                            .frame(width: 380)
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                        }
                    }
                }
            } else {
                ContentUnavailableView(
                    "No Script Selected",
                    systemImage: "doc.text.magnifyingglass",
                    description: Text("Select a script from the sidebar or create a new one.")
                )
            }
        }
        .frame(minWidth: 900, minHeight: 450)
        .task {
            // Restore saved settings
            if let saved = ProviderChoice(rawValue: AppSettings.shared.defaultProvider) {
                selectedProvider = saved
            }
            if let savedTone = SpeechTone(rawValue: AppSettings.shared.speechTone) {
                selectedTone = savedTone
            }
        }
        .onChange(of: selectedScript) {
            // Close assistant and nil out conversation when switching scripts
            showAssistant = false
            conversation = nil
        }
        .onChange(of: selectedTone) {
            AppSettings.shared.speechTone = selectedTone.rawValue
        }
        .onChange(of: targetMinutes) {
            selectedScript?.targetDuration = Double(targetMinutes)
        }
        .alert("Provider Unavailable", isPresented: $showingProviderError) {
            Button("OK") {}
        } message: {
            Text(providerError ?? "")
        }
        .alert("Import Error", isPresented: $showingImportError) {
            Button("OK") {}
        } message: {
            Text(importError ?? "Unknown error")
        }
    }

    // MARK: - Assistant Panel

    private func toggleAssistant(for script: Script) {
        if showAssistant {
            withAnimation(.easeInOut(duration: 0.2)) {
                showAssistant = false
            }
            return
        }

        // Restore target duration from script if saved
        if let saved = script.targetDuration, saved > 0 {
            targetMinutes = Int(saved)
        }

        // Show the panel immediately, load provider in background
        withAnimation(.easeInOut(duration: 0.2)) {
            showAssistant = true
        }

        if conversation == nil {
            Task {
                await initializeConversation(for: script)
            }
        }
    }

    private func initializeConversation(for script: Script) async {
        isLoadingProvider = true
        defer { isLoadingProvider = false }
        guard let provider = await makeProvider() else { return }

        script.targetDuration = Double(targetMinutes)

        let slides = script.sortedSections.map { $0.toSlideContent() }
        conversation = ConversationManager(
            provider: provider,
            slides: slides,
            script: script,
            targetDurationMinutes: targetMinutes,
            tone: selectedTone,
            modelContext: modelContext
        )
    }

    private func makeProvider() async -> (any LLMProvider)? {
        switch selectedProvider {
        case .foundationModel:
            let fm = FoundationModelProvider()
            guard await fm.isAvailable else {
                providerError = "On-device AI requires Apple Silicon with macOS 26. The model may still be downloading."
                showingProviderError = true
                return nil
            }
            return fm
        case .mlxLocal:
            let manager = MLXModelManager.shared
            if await manager.selectedModel == nil {
                let savedId = AppSettings.shared.mlxSelectedModelId
                if !savedId.isEmpty {
                    for _ in 0..<10 {
                        try? await Task.sleep(for: .milliseconds(100))
                        if await manager.selectedModel != nil { break }
                    }
                }
            }
            guard let modelInfo = await manager.selectedModel else {
                providerError = "No local model selected. Open Settings -> Models to download one."
                showingProviderError = true
                return nil
            }
            if await manager.loadState != .loaded {
                do {
                    try await manager.loadModel(modelInfo)
                } catch {
                    providerError = "Failed to load model: \(error.localizedDescription)"
                    showingProviderError = true
                    return nil
                }
            }
            return MLXProvider(modelInfo: modelInfo)
        case .claudeCLI:
            let claude = ClaudeCLIProvider(model: .sonnet)
            guard await claude.isAvailable else {
                providerError = "Claude Code CLI not found. Install it with: npm install -g @anthropic-ai/claude-code"
                showingProviderError = true
                return nil
            }
            return claude
        case .lmStudio:
            let baseURL = URL(string: AppSettings.shared.lmStudioBaseURL) ?? URL(string: "http://localhost:1234")!
            let lm = LMStudioProvider(baseURL: baseURL)
            guard await lm.isAvailable else {
                providerError = "LM Studio is not running. Please start LM Studio and load a model."
                showingProviderError = true
                return nil
            }
            return lm
        }
    }

    private func switchProvider() {
        Task {
            if selectedProvider != .mlxLocal {
                await MLXModelManager.shared.unloadModel()
            }
            if selectedProvider != .foundationModel,
               let fm = conversation?.provider as? FoundationModelProvider {
                fm.resetSession()
            }
            guard let provider = await makeProvider() else { return }
            if let conversation {
                conversation.switchProvider(provider)
            } else if let script = selectedScript {
                await initializeConversation(for: script)
            }
        }
    }

    // MARK: - PPTX Import

    private func importPPTX() {
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

            let slides = result.slides
            let pptxURL = url
            Task { @MainActor in
                await Task.yield()
                await generateSlidePreviews(for: script, slides: slides, pptxURL: pptxURL)

                // Open assistant panel after import
                toggleAssistant(for: script)
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
                    existing.label = slide.title.isEmpty ? "Slide \(slide.slideNumber)" : slide.title
                    existing.originalBodyText = slide.bodyText
                    existing.originalNotes = slide.notes
                } else {
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

            let newSlideNumbers = Set(result.slides.map(\.slideNumber))
            let removedSections = script.sections.filter { !newSlideNumbers.contains($0.slideNumber) }
            for section in removedSections {
                modelContext.delete(section)
                script.sections.removeAll { $0 === section }
            }

            script.modifiedAt = .now
            try? modelContext.save()

            let slides = result.slides
            let pptxURL = url
            Task { @MainActor in
                await Task.yield()
                await generateSlidePreviews(for: script, slides: slides, pptxURL: pptxURL)
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

    @MainActor
    private func generateSlidePreviews(for script: Script, slides: [SlideContent], pptxURL: URL) async {
        let ctx = modelContext
        let sectionIndex = Dictionary(script.sections.map { ($0.slideNumber, $0) }, uniquingKeysWith: { a, _ in a })

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
}

#Preview {
    ScriptManagerView()
        .modelContainer(PreviewSampleData.container)
}
