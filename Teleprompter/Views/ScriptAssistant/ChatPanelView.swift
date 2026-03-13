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
                    VStack(spacing: 0) {
                        let visible = conversation.visibleMessages
                        let lastAssistantId = visible.last(where: { $0.role == .assistant })?.id

                        ForEach(Array(visible.enumerated()), id: \.element.id) { index, message in
                            ChatMessageView(
                                message: message,
                                isLastAssistantMessage: message.role == .assistant && message.id == lastAssistantId,
                                onDelete: {
                                    conversation.deleteMessage(message)
                                }
                            )

                            if index < visible.count - 1 {
                                Divider()
                                    .padding(.horizontal, 16)
                            }
                        }

                        if conversation.isStreaming {
                            Divider()
                                .padding(.horizontal, 16)
                            streamingMessageView
                        }

                        Color.clear
                            .frame(height: 1)
                            .id("chatBottom")
                    }
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .defaultScrollAnchor(.bottom)
                .onChange(of: conversation.visibleMessages.count) {
                    proxy.scrollTo("chatBottom")
                }
                .onChange(of: conversation.isStreaming) {
                    proxy.scrollTo("chatBottom")
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

            inputBar
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

    private var inputBar: some View {
        VStack(spacing: 0) {
            Divider()

            HStack(spacing: 8) {
                TextField("Ask about your script...", text: $inputText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...10)
                    .font(.system(size: 14))
                    .focused($isInputFocused)
                    .onKeyPress(.return, phases: .down) { keyPress in
                        if keyPress.modifiers.contains(.shift) {
                            inputText += "\n"
                            return .handled
                        }
                        sendMessage()
                        return .handled
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

    private var streamingMessageView: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Assistant")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)

            if conversation.currentStreamingText.isEmpty {
                TypingIndicatorView()
            } else {
                HStack(alignment: .bottom, spacing: 0) {
                    // Use plain text during streaming to avoid expensive markdown re-parsing on every token
                    Text(conversation.currentStreamingText)
                        .font(.system(size: 15))
                        .lineSpacing(6)
                        .textSelection(.enabled)

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
