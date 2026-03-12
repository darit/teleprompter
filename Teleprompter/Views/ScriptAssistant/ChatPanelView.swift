// Teleprompter/Views/ScriptAssistant/ChatPanelView.swift
import SwiftUI

struct ChatPanelView: View {
    @Bindable var conversation: ConversationManager
    @State private var inputText = ""
    @FocusState private var isInputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Context bar
            HStack(spacing: 8) {
                Text("\(conversation.slideCount) slides loaded")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)

                Spacer()

                Text(conversation.providerName)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial)

            Divider()

            // Messages
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(conversation.visibleMessages) { message in
                            ChatMessageView(message: message)
                                .id(message.id)
                        }

                        if conversation.isStreaming {
                            streamingBubble
                                .id("streaming")
                        }

                        // Invisible anchor at the very bottom
                        Color.clear
                            .frame(height: 1)
                            .id("bottom")
                    }
                    .padding(16)
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

            Divider()

            // Input bar
            HStack(spacing: 8) {
                TextField("Type a message...", text: $inputText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...5)
                    .focused($isInputFocused)
                    .onSubmit {
                        sendMessage()
                    }

                Button {
                    sendMessage()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 22))
                }
                .buttonStyle(.plain)
                .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || conversation.isStreaming)
            }
            .padding(12)
            .background(.ultraThinMaterial)
        }
        .onAppear {
            isInputFocused = true
        }
    }

    private var streamingBubble: some View {
        HStack {
            let displayText = conversation.currentStreamingText.isEmpty
                ? "Thinking..."
                : conversation.currentStreamingText

            Text(attributedMarkdown(displayText))
                .font(.system(size: 13))
                .lineSpacing(4)
                .textSelection(.enabled)
                .padding(12)
                .background {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.primary.opacity(0.04))
                }
                .frame(maxWidth: 500, alignment: .leading)

            Spacer(minLength: 60)
        }
    }

    private func attributedMarkdown(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(text)
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
