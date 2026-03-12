// Teleprompter/Views/ScriptAssistant/ScriptAssistantView.swift
import SwiftUI
import SwiftData

struct ScriptAssistantView: View {
    let script: Script
    let slides: [SlideContent]
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var conversation: ConversationManager?
    @State private var targetMinutes: Int = 15
    @State private var hasStarted = false
    @State private var providerError: String?
    @State private var showingProviderError = false

    var body: some View {
        Group {
            if let conversation {
                HSplitView {
                    ChatPanelView(conversation: conversation)
                        .frame(minWidth: 350, idealWidth: 450)

                    ScriptPreviewPanel(
                        script: script,
                        totalSlides: slides.count,
                        targetDurationMinutes: targetMinutes
                    )
                    .frame(minWidth: 300, idealWidth: 350)
                }
            } else {
                startView
            }
        }
        .frame(minWidth: 750, minHeight: 500)
        .navigationTitle("Script Assistant -- \(script.name)")
        .alert("Provider Unavailable", isPresented: $showingProviderError) {
            Button("OK") {}
        } message: {
            Text(providerError ?? "")
        }
    }

    private var startView: some View {
        VStack(spacing: 20) {
            Text("Ready to generate your script")
                .font(.system(size: 18, weight: .semibold))

            Text("\(slides.count) slides loaded from your presentation")
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                Text("Target duration:")
                    .font(.system(size: 13))
                Picker("", selection: $targetMinutes) {
                    Text("5 min").tag(5)
                    Text("10 min").tag(10)
                    Text("15 min").tag(15)
                    Text("20 min").tag(20)
                    Text("30 min").tag(30)
                    Text("45 min").tag(45)
                    Text("60 min").tag(60)
                }
                .frame(width: 100)
            }

            Button("Start") {
                startConversation()
            }
            .buttonStyle(.glass)
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func startConversation() {
        let provider = ClaudeCLIProvider(model: .sonnet)

        guard provider.isAvailable else {
            providerError = "Claude Code CLI not found. Install it with: npm install -g @anthropic-ai/claude-code"
            showingProviderError = true
            return
        }

        let manager = ConversationManager(
            provider: provider,
            slides: slides,
            script: script,
            targetDurationMinutes: targetMinutes,
            modelContext: modelContext
        )

        conversation = manager
        hasStarted = true

        Task {
            await manager.start()
        }
    }
}
