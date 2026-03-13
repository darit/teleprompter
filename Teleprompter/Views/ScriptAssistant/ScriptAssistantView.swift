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
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var conversation: ConversationManager?
    @State private var targetMinutes: Int = 15
    @State private var selectedProvider: ProviderChoice = .claudeCLI
    @State private var providerError: String?
    @State private var showingProviderError = false

    var body: some View {
        VStack(spacing: 0) {
            // Top bar with controls
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
                    .disabled(conversation?.visibleMessages.isEmpty ?? true)

                    Button("Done") {
                        dismiss()
                    }
                    .buttonStyle(.glass)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial)

            Divider()

            // Main content
            HSplitView {
                if let conversation {
                    ChatPanelView(conversation: conversation)
                        .frame(minWidth: 400, idealWidth: 480)
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .frame(minWidth: 400, idealWidth: 480)
                }

                ScriptPreviewPanel(
                    script: script,
                    totalSlides: slides.count,
                    targetDurationMinutes: targetMinutes
                )
                .frame(minWidth: 350, idealWidth: 400)
            }
        }
        .frame(minWidth: 800, minHeight: 600)
        .alert("Provider Unavailable", isPresented: $showingProviderError) {
            Button("OK") {}
        } message: {
            Text(providerError ?? "")
        }
        .onAppear {
            if let saved = script.targetDuration, saved > 0 {
                targetMinutes = Int(saved)
            }
            initializeConversation()
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
