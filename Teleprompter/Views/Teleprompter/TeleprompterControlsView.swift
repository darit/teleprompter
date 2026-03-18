import SwiftUI

struct TeleprompterControlsView: View {
    @Bindable var state: TeleprompterState

    var body: some View {
        HStack(spacing: 16) {
            // Transport controls
            HStack(spacing: 12) {
                Button {
                    state.jumpBackward()
                } label: {
                    VStack(spacing: 2) {
                        Image(systemName: "backward.end.fill")
                            .font(.system(size: 12))
                        shortcutLabel("\u{21E7}\u{2318}\u{2190}")
                    }
                }
                .buttonStyle(.plain)
                .help("Previous section (Cmd+Shift+Left)")

                Button {
                    state.togglePlayPause()
                } label: {
                    VStack(spacing: 2) {
                        Image(systemName: state.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 16))
                        shortcutLabel("\u{21E7}\u{2318}P")
                    }
                    .frame(width: 36, height: 38)
                }
                .buttonStyle(.plain)
                .help(state.isPlaying ? "Pause (Cmd+Shift+P)" : "Play (Cmd+Shift+P)")

                Button {
                    state.jumpForward()
                } label: {
                    VStack(spacing: 2) {
                        Image(systemName: "forward.end.fill")
                            .font(.system(size: 12))
                        shortcutLabel("\u{21E7}\u{2318}\u{2192}")
                    }
                }
                .buttonStyle(.plain)
                .help("Next section (Cmd+Shift+Right)")
            }

            Divider().frame(height: 24)

            // WPM pace control
            HStack(spacing: 6) {
                Button {
                    state.decreaseSpeed()
                } label: {
                    Image(systemName: "minus")
                        .font(.system(size: 10))
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                VStack(spacing: 1) {
                    Text("\(Int(state.scrollSpeed))")
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    Text("WPM")
                        .font(.system(size: 7, weight: .medium))
                        .foregroundStyle(.tertiary)
                }
                .frame(width: 40)

                Button {
                    state.increaseSpeed()
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 10))
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .help("Speaking pace (words per minute)")

            Divider().frame(height: 24)

            // Font size
            HStack(spacing: 6) {
                Button {
                    state.decreaseFontSize()
                } label: {
                    Image(systemName: "textformat.size.smaller")
                        .font(.system(size: 10))
                }
                .buttonStyle(.plain)

                Text("\(Int(state.fontSize))")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .frame(width: 22)

                Button {
                    state.increaseFontSize()
                } label: {
                    Image(systemName: "textformat.size.larger")
                        .font(.system(size: 10))
                }
                .buttonStyle(.plain)
            }
            .help("Font size")

            Divider().frame(height: 24)

            // Background opacity
            HStack(spacing: 4) {
                Image(systemName: "square.filled.on.square")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)

                Slider(value: $state.backgroundOpacity, in: 0.0...1.0, step: 0.05)
                    .frame(width: 50)
            }
            .help("Background opacity")

            // Window opacity
            HStack(spacing: 4) {
                Image(systemName: "circle.lefthalf.filled")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)

                Slider(value: $state.opacity, in: 0.2...1.0, step: 0.1)
                    .frame(width: 50)
                    .onChange(of: state.opacity) {
                        TeleprompterWindowController.shared.updateOpacity()
                    }
            }
            .help("Window opacity")

            Spacer()

            // Close
            Button {
                TeleprompterWindowController.shared.close()
                GlobalShortcutManager.shared.stop()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Close teleprompter")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .glassEffect(.regular.interactive(), in: .rect)
    }

    private func shortcutLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .medium))
            .foregroundStyle(.tertiary)
    }
}
