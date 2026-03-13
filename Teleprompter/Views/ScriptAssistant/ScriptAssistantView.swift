// Teleprompter/Views/ScriptAssistant/ScriptAssistantView.swift
import SwiftUI
import SwiftData

enum ProviderChoice: String, CaseIterable {
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
    @State private var providerError: String?
    @State private var showingProviderError = false
    @State private var sectionSnapshots: [SectionSnapshot] = []
    @State private var isConversationStreaming = false
    @State private var activeSlide: Int?
    @State private var previewWidth: CGFloat = 380

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
                            await conversation.generateAllSlides()
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
        .onAppear {
            if let saved = script.targetDuration, saved > 0 {
                targetMinutes = Int(saved)
            }
            sectionSnapshots = initialSnapshots
            initializeConversation()
            conversation?.onSectionsChanged = { [self] in
                refreshSnapshots()
            }
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
                .frame(width: 170)
                .onChange(of: selectedProvider) {
                    switchProvider()
                }

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
        // Access count first to force SwiftData to fault in the relationship
        let sections = script.sections
        _ = sections.count

        let new = sections.map { section in
            SectionSnapshot(
                slideNumber: section.slideNumber,
                label: section.label,
                content: section.content,
                accentColorHex: section.accentColorHex
            )
        }
        if new != sectionSnapshots {
            sectionSnapshots = new
        }

        // Sync streaming state from conversation without SwiftUI observation
        let streaming = conversation?.isStreaming ?? false
        if streaming != isConversationStreaming {
            isConversationStreaming = streaming
        }
        let slide = conversation?.activelyStreamingSlideNumber
        if slide != activeSlide {
            activeSlide = slide
        }
    }

    private func makeProvider() -> (any LLMProvider)? {
        switch selectedProvider {
        case .claudeCLI:
            let claude = ClaudeCLIProvider(model: .sonnet)
            guard claude.isAvailable else {
                providerError = "Claude Code CLI not found. Install it with: npm install -g @anthropic-ai/claude-code"
                showingProviderError = true
                return nil
            }
            return claude
        case .lmStudio:
            let lm = LMStudioProvider()
            guard lm.isAvailable else {
                providerError = "LM Studio is not running. Please start LM Studio and load a model."
                showingProviderError = true
                return nil
            }
            return lm
        }
    }

    private func initializeConversation() {
        guard conversation == nil else { return }
        guard let provider = makeProvider() else { return }

        script.targetDuration = Double(targetMinutes)

        conversation = ConversationManager(
            provider: provider,
            slides: slides,
            script: script,
            targetDurationMinutes: targetMinutes,
            modelContext: modelContext
        )
    }

    private func switchProvider() {
        guard let provider = makeProvider() else { return }
        if let conversation {
            conversation.switchProvider(provider)
        } else {
            initializeConversation()
        }
    }
}
