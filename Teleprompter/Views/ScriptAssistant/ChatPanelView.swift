// Teleprompter/Views/ScriptAssistant/ChatPanelView.swift
import SwiftUI

struct ChatPanelView: View {
    @Bindable var conversation: ConversationManager
    @State private var inputText = ""
    @FocusState private var isInputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Messages
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(conversation.visibleMessages.enumerated()), id: \.element.id) { index, message in
                            let isLastAssistant = message.role == .assistant &&
                                message.id == conversation.visibleMessages.last(where: { $0.role == .assistant })?.id

                            ChatMessageView(message: message, isLastAssistantMessage: isLastAssistant)

                            if index < conversation.visibleMessages.count - 1 {
                                Divider()
                                    .padding(.horizontal, 16)
                            }
                        }

                        if conversation.isStreaming {
                            Divider()
                                .padding(.horizontal, 16)
                            streamingMessageView
                                .id("streaming")
                        }

                        Color.clear
                            .frame(height: 1)
                            .id("bottom")
                    }
                    .padding(.vertical, 12)
                }
                .defaultScrollAnchor(.bottom)
                .onChange(of: conversation.messages.count) {
                    withAnimation {
                        proxy.scrollTo("bottom", anchor: .bottom)
                    }
                }
                .onChange(of: conversation.currentStreamingText) {
                    if conversation.isStreaming {
                        proxy.scrollTo("bottom", anchor: .bottom)
                    }
                }
            }

            if let error = conversation.error {
                HStack {
                    Image(systemName: "exclamationmark.triangle")
                    Text(error)
                        .font(.system(size: 11))
                }
                .foregroundStyle(.red)
                .padding(8)
            }

            // Input bar
            VStack(spacing: 0) {
                Divider()

                HStack(alignment: .bottom, spacing: 8) {
                    TextField("Ask about your script...", text: $inputText, axis: .vertical)
                        .textFieldStyle(.plain)
                        .lineLimit(1...8)
                        .font(.system(size: 14))
                        .focused($isInputFocused)
                        .onSubmit {
                            sendMessage()
                        }

                    Button {
                        if conversation.isStreaming {
                            conversation.stopStreaming()
                        } else {
                            sendMessage()
                        }
                    } label: {
                        Image(systemName: conversation.isStreaming ? "stop.circle.fill" : "arrow.up.circle.fill")
                            .font(.system(size: 24))
                            .foregroundStyle(conversation.isStreaming ? .red : .accentColor)
                    }
                    .buttonStyle(.plain)
                    .disabled(!conversation.isStreaming && inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(.ultraThinMaterial)
                        .overlay {
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color(nsColor: .quaternaryLabelColor), lineWidth: 0.5)
                        }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
        }
        .onAppear {
            isInputFocused = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .regenerateLastResponse)) { _ in
            Task {
                await conversation.regenerateLastResponse()
            }
        }
    }

    private var streamingMessageView: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Assistant")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)

            if conversation.currentStreamingText.isEmpty {
                TypingIndicatorView()
            } else {
                HStack(alignment: .bottom, spacing: 0) {
                    MarkdownContentView(text: conversation.currentStreamingText)

                    BlinkingCursorView()
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !conversation.isStreaming else { return }
        inputText = ""
        Task {
            await conversation.send(text)
        }
    }
}

private struct BlinkingCursorView: View {
    @State private var visible = true

    var body: some View {
        Rectangle()
            .fill(Color.primary)
            .frame(width: 2, height: 16)
            .opacity(visible ? 1 : 0)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.53).repeatForever(autoreverses: true)) {
                    visible = false
                }
            }
    }
}
