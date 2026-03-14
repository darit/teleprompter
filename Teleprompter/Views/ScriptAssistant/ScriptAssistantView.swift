// Teleprompter/Views/ScriptAssistant/ScriptAssistantView.swift
import SwiftUI
import SwiftData

enum ProviderChoice: String, CaseIterable {
    case foundationModel = "Apple On-Device"
    case mlxLocal = "Local Model (MLX)"
    case claudeCLI = "Claude Code CLI"
    case lmStudio = "LM Studio (Local)"
}

struct ScriptAssistantView: View {
    let script: Script
    let slides: [SlideContent]
    let initialSnapshots: [SectionSnapshot]
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var conversation: ConversationManager?
    @State private var targetMinutes: Int = 10
    @State private var selectedProvider: ProviderChoice = .lmStudio
    @State private var selectedTone: SpeechTone = .conversational
    @State private var providerError: String?
    @State private var showingProviderError = false
    @State private var sectionSnapshots: [SectionSnapshot] = []
    @State private var isConversationStreaming = false
    @State private var activeSlide: Int?
    @State private var previewWidth: CGFloat = 380
    /// Guard against re-entrant snapshot updates during CA commit
    @State private var isRefreshing = false

    var body: some View {
        VStack(spacing: 0) {
            // Top bar with controls
            assistantToolbar

            Divider()

            // Main content
            HStack(spacing: 0) {
                if let conversation {
                    ChatPanelView(conversation: conversation)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

                // Draggable divider
                Rectangle()
                    .fill(Color(nsColor: .separatorColor))
                    .frame(width: 1)
                    .overlay {
                        Rectangle()
                            .fill(Color.clear)
                            .frame(width: 8)
                            .contentShape(Rectangle())
                            .onHover { hovering in
                                if hovering {
                                    NSCursor.resizeLeftRight.push()
                                } else {
                                    NSCursor.pop()
                                }
                            }
                            .gesture(
                                DragGesture(minimumDistance: 1)
                                    .onChanged { value in
                                        let newWidth = previewWidth - value.translation.width
                                        previewWidth = min(max(newWidth, 280), 600)
                                    }
                            )
                    }

                ScriptPreviewPanel(
                    sections: sectionSnapshots,
                    totalSlides: slides.count,
                    targetDurationMinutes: targetMinutes,
                    activeSlideNumber: activeSlide,
                    isStreaming: isConversationStreaming,
                    parallelGeneratingSlides: conversation?.parallelGeneratingSlides ?? [],
                    isGeneratingAll: conversation?.isGeneratingAll ?? false,
                    onGenerate: { slideNumber in
                        guard let conversation else { return }
                        Task {
                            await conversation.generateSlide(slideNumber)
                        }
                    },
                    onGenerateAll: {
                        guard let conversation else { return }
                        Task {
                            await conversation.generateAllSlides(maxConcurrency: AppSettings.shared.maxParallelSlides)
                        }
                    },
                    onStopGenerateAll: {
                        conversation?.stopGenerateAll()
                    }
                )
                .frame(width: previewWidth)
                .frame(maxHeight: .infinity)
            }
        }
        .frame(minWidth: 900, minHeight: 600)
        .alert("Provider Unavailable", isPresented: $showingProviderError) {
            Button("OK") {}
        } message: {
            Text(providerError ?? "")
        }
        .task {
            if let saved = script.targetDuration, saved > 0 {
                targetMinutes = Int(saved)
            }
            if let savedTone = SpeechTone(rawValue: AppSettings.shared.speechTone) {
                selectedTone = savedTone
            }
            sectionSnapshots = initialSnapshots
            await initializeConversation()
            conversation?.onSectionsChanged = { [self] in
                refreshSnapshots()
            }
        }
        .onChange(of: selectedTone) {
            AppSettings.shared.speechTone = selectedTone.rawValue
        }
    }

    private var assistantToolbar: some View {
        HStack(spacing: 16) {
            Text("Script Assistant")
                .font(.system(size: 13, weight: .semibold))

            Spacer()

            HStack(spacing: 12) {
                Picker("", selection: $selectedProvider) {
                    ForEach(ProviderChoice.allCases, id: \.self) { choice in
                        Text(choice.rawValue).tag(choice)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 190)
                .onChange(of: selectedProvider) {
                    switchProvider()
                }

                Picker("", selection: $selectedTone) {
                    let grouped = Dictionary(grouping: SpeechTone.allCases, by: \.category)
                    ForEach(["Tone", "Presentation"], id: \.self) { category in
                        Section(category) {
                            ForEach(grouped[category] ?? []) { tone in
                                Text(tone.label).tag(tone)
                            }
                        }
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 150)
                .help("Presentation style")

                Picker("", selection: $targetMinutes) {
                    Text("5 min").tag(5)
                    Text("10 min").tag(10)
                    Text("15 min").tag(15)
                    Text("20 min").tag(20)
                    Text("30 min").tag(30)
                    Text("45 min").tag(45)
                    Text("60 min").tag(60)
                }
                .frame(width: 80)
                .onChange(of: targetMinutes) {
                    script.targetDuration = Double(targetMinutes)
                }
            }

            Spacer()

            HStack(spacing: 8) {
                Button {
                    conversation?.clearHistory()
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .help("Clear chat history")

                Button("Done") {
                    NSApp.keyWindow?.close()
                }
                .buttonStyle(.glass)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }

    private func refreshSnapshots() {
        // Guard against re-entrant calls during CA commit transactions
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        // Defer state mutations to the next run loop tick to avoid
        // triggering SwiftUI layout updates mid-CA commit.
        DispatchQueue.main.async { [self] in
            let sections = script.sections
            _ = sections.count

            let new = sections.map { $0.toSnapshot() }
            if new != sectionSnapshots {
                sectionSnapshots = new
            }

            let streaming = conversation?.isStreaming ?? false
            if streaming != isConversationStreaming {
                isConversationStreaming = streaming
            }
            let slide = conversation?.activelyStreamingSlideNumber
            if slide != activeSlide {
                activeSlide = slide
            }
        }
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
            guard let modelInfo = await manager.selectedModel else {
                providerError = "No local model selected. Open Settings > Models to download one."
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

    private func initializeConversation() async {
        guard conversation == nil else { return }
        guard let provider = await makeProvider() else { return }

        script.targetDuration = Double(targetMinutes)

        conversation = ConversationManager(
            provider: provider,
            slides: slides,
            script: script,
            targetDurationMinutes: targetMinutes,
            tone: selectedTone,
            modelContext: modelContext
        )
    }

    private func switchProvider() {
        Task {
            // Unload MLX model when switching away to free GPU memory
            if selectedProvider != .mlxLocal {
                await MLXModelManager.shared.unloadModel()
            }
            // Reset Foundation Models session when switching away
            if selectedProvider != .foundationModel,
               let fm = conversation?.provider as? FoundationModelProvider {
                fm.resetSession()
            }
            guard let provider = await makeProvider() else { return }
            if let conversation {
                conversation.switchProvider(provider)
            } else {
                await initializeConversation()
            }
        }
    }
}
