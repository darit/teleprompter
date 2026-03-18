// Teleprompter/Views/ScriptAssistant/AssistantPanelView.swift
import SwiftUI

struct AssistantPanelView: View {
    @Bindable var conversation: ConversationManager
    @Binding var selectedProvider: ProviderChoice
    @Binding var selectedTone: SpeechTone
    @Binding var targetMinutes: Int
    var onClose: () -> Void
    var onSwitchProvider: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            panelHeader

            Divider()

            // Chat body
            ChatPanelView(conversation: conversation)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Context meter (only for providers with finite context windows)
            if let ratio = conversation.contextUsageRatio {
                contextMeter(ratio: ratio)
            }
        }
    }

    // MARK: - Header

    private var panelHeader: some View {
        VStack(spacing: 8) {
            // Top row: title + close
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                Text("Assistant")
                    .font(.system(size: 12, weight: .semibold))

                Spacer()

                // Generate All / Stop
                generateButton

                Button {
                    conversation.clearHistory()
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Clear chat history")

                Button {
                    onClose()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Close assistant")
            }

            // Controls row — no glass here, it's inside the header glass already
            HStack(spacing: 2) {
                Picker("", selection: $selectedProvider) {
                    ForEach(ProviderChoice.allCases, id: \.self) { choice in
                        Text(choice.rawValue).tag(choice)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 160)
                .onChange(of: selectedProvider) {
                    AppSettings.shared.defaultProvider = selectedProvider.rawValue
                    onSwitchProvider()
                }

                dividerDot

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
                .frame(width: 130)
                .help("Presentation style")

                dividerDot

                Picker("", selection: $targetMinutes) {
                    Text("5 min").tag(5)
                    Text("10 min").tag(10)
                    Text("15 min").tag(15)
                    Text("20 min").tag(20)
                    Text("30 min").tag(30)
                    Text("45 min").tag(45)
                    Text("60 min").tag(60)
                }
                .frame(width: 72)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(.white.opacity(0.05))
            }

            // Generation progress
            if conversation.isGeneratingAll {
                let done = conversation.slideCount - conversation.parallelGeneratingSlides.count
                HStack(spacing: 4) {
                    ProgressView()
                        .scaleEffect(0.5)
                        .frame(width: 12, height: 12)
                    Text("Generating \(done)/\(conversation.slideCount)...")
                        .font(.system(size: 10))
                        .foregroundStyle(.orange)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
        .zIndex(1)
    }

    private var generateButton: some View {
        Group {
            if conversation.isGeneratingAll {
                Button {
                    conversation.stopGenerateAll()
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "stop.fill")
                            .font(.system(size: 7))
                        Text("Stop")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
            } else if !conversation.isStreaming {
                Button {
                    Task {
                        await conversation.generateAllSlides(maxConcurrency: AppSettings.shared.maxParallelSlides)
                    }
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 8))
                        Text("Generate All")
                            .font(.system(size: 10, weight: .medium))
                    }
                }
                .buttonStyle(.plain)
                .help("Generate scripts for all slides")
            }
        }
    }

    private var dividerDot: some View {
        Circle()
            .fill(.quaternary)
            .frame(width: 3, height: 3)
    }

    // MARK: - Context Meter

    private func contextMeter(ratio: Double) -> some View {
        let window = conversation.provider.contextWindowSize ?? 0
        let used = conversation.estimatedTokensUsed
        let color: Color = ratio > 0.95 ? .red : ratio > 0.8 ? .orange : .green

        return VStack(spacing: 0) {
            Divider()

            HStack(spacing: 8) {
                ProgressView(value: min(ratio, 1.0))
                    .tint(color)
                    .frame(width: 60)

                Text(formatTokenCount(used) + " / " + formatTokenCount(window))
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.secondary)

                if conversation.isContextCritical {
                    Text("Context nearly full")
                        .font(.system(size: 9))
                        .foregroundStyle(.red)
                } else if conversation.isContextWarning {
                    Text("Context filling up")
                        .font(.system(size: 9))
                        .foregroundStyle(.orange)
                }

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.bar)
        }
    }

    private func formatTokenCount(_ count: Int) -> String {
        if count >= 1000 {
            return String(format: "%.1fK", Double(count) / 1000.0)
        }
        return "\(count)"
    }
}
