// Teleprompter/Views/ScriptAssistant/ChatPanelView.swift
import SwiftUI

struct ChatPanelView: View {
    @Bindable var conversation: ConversationManager
    @State private var inputText = ""
    @FocusState private var isInputFocused: Bool
    @State private var isAtBottom = true
    @State private var hasNewContent = false

    var body: some View {
        VStack(spacing: 0) {
            // Messages
            ScrollViewReader { proxy in
                ZStack(alignment: .bottomTrailing) {
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

                            GeometryReader { geo in
                                Color.clear
                                    .preference(key: ScrollOffsetKey.self,
                                                value: geo.frame(in: .named("chatScroll")).maxY)
                            }
                            .frame(height: 0)
                        }
                        .padding(.vertical, 12)
                    }
                    .coordinateSpace(name: "chatScroll")
                    .defaultScrollAnchor(.bottom)
                    .onPreferenceChange(ScrollOffsetKey.self) { maxY in
                        // When the bottom anchor is visible (maxY > 0 means it's in the viewport),
                        // we consider the user to be at the bottom.
                        let atBottom = maxY > 0
                        if atBottom {
                            hasNewContent = false
                        }
                        isAtBottom = atBottom
                    }
                    .onChange(of: conversation.messages.count) {
                        if isAtBottom {
                            withAnimation {
                                proxy.scrollTo("bottom", anchor: .bottom)
                            }
                        } else {
                            hasNewContent = true
                        }
                    }
                    .onChange(of: conversation.currentStreamingText) {
                        if conversation.isStreaming {
                            proxy.scrollTo("bottom", anchor: .bottom)
                        }
                    }

                    if !isAtBottom {
                        Button {
                            isAtBottom = true
                            hasNewContent = false
                            withAnimation {
                                proxy.scrollTo("bottom", anchor: .bottom)
                            }
                        } label: {
                            ZStack {
                                Circle()
                                    .fill(.ultraThinMaterial)
                                    .frame(width: 32, height: 32)
                                    .shadow(color: .black.opacity(0.1), radius: 4, y: 2)

                                Image(systemName: "chevron.down")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(.secondary)

                                if hasNewContent {
                                    Circle()
                                        .fill(Color.accentColor)
                                        .frame(width: 8, height: 8)
                                        .offset(x: 10, y: -10)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .padding(.trailing, 16)
                        .padding(.bottom, 16)
                        .transition(.opacity.combined(with: .scale))
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

private struct ScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
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
