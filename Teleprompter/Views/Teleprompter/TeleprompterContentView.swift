import SwiftUI

struct TeleprompterContentView: View {
    @Bindable var state: TeleprompterState

    var body: some View {
        VStack(spacing: 0) {
            // Current section indicator
            HStack(spacing: 8) {
                if state.currentSectionIndex < state.sections.count {
                    let current = state.sections[state.currentSectionIndex]
                    SlidePillView(slideNumber: current.slideNumber, colorHex: current.accentColorHex)
                    Text(current.label)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text("\(state.currentSectionIndex + 1) / \(state.sections.count)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial)

            Divider()

            // Text zone
            TeleprompterTextView(state: state)

            Divider()

            // Controls zone (always interactive)
            TeleprompterControlsView(state: state)
        }
        .background(.black.opacity(state.backgroundOpacity))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
