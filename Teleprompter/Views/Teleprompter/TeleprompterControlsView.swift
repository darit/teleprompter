import SwiftUI

struct TeleprompterControlsView: View {
    @Bindable var state: TeleprompterState

    var body: some View {
        HStack(spacing: 16) {
            // Lock toggle
            Button {
                state.toggleClickThrough()
                TeleprompterWindowController.shared.updateClickThrough()
            } label: {
                Image(systemName: state.isClickThrough ? "lock.open" : "lock")
                    .font(.system(size: 14))
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .help(state.isClickThrough ? "Lock (click-through ON)" : "Unlock (click-through OFF)")

            Divider().frame(height: 20)

            // Transport controls
            HStack(spacing: 12) {
                Button {
                    state.jumpBackward()
                } label: {
                    Image(systemName: "backward.end.fill")
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .help("Previous section")

                Button {
                    state.togglePlayPause()
                } label: {
                    Image(systemName: state.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 16))
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                .help(state.isPlaying ? "Pause" : "Play")

                Button {
                    state.jumpForward()
                } label: {
                    Image(systemName: "forward.end.fill")
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .help("Next section")
            }

            Divider().frame(height: 20)

            // Speed
            HStack(spacing: 4) {
                Button {
                    state.decreaseSpeed()
                } label: {
                    Image(systemName: "minus")
                        .font(.system(size: 10))
                }
                .buttonStyle(.plain)

                Text("\(String(format: "%.2g", state.scrollSpeed))x")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .frame(width: 32)

                Button {
                    state.increaseSpeed()
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 10))
                }
                .buttonStyle(.plain)
            }
            .help("Scroll speed")

            Divider().frame(height: 20)

            // Opacity
            HStack(spacing: 4) {
                Image(systemName: "circle.lefthalf.filled")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)

                Slider(value: $state.opacity, in: 0.2...1.0, step: 0.1)
                    .frame(width: 60)
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
        .background(.ultraThinMaterial)
    }
}
