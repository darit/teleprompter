import SwiftUI

struct TeleprompterTextView: View {
    @Bindable var state: TeleprompterState
    @State private var scrollProxy: ScrollViewProxy?
    @State private var timer: Timer?

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(state.sections.enumerated()), id: \.element.id) { index, section in
                        sectionView(section: section, index: index)
                            .id(index)
                    }

                    // Bottom padding so last section can scroll to top
                    Spacer()
                        .frame(height: 300)
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)
            }
            .onAppear {
                scrollProxy = proxy
            }
            .onChange(of: state.currentSectionIndex) { _, newIndex in
                withAnimation(.easeInOut(duration: 0.5)) {
                    proxy.scrollTo(newIndex, anchor: .top)
                }
            }
            .onChange(of: state.isPlaying) { _, playing in
                if playing {
                    startAutoScroll()
                } else {
                    stopAutoScroll()
                }
            }
        }
        .onDisappear {
            stopAutoScroll()
        }
    }

    private func sectionView(section: TeleprompterSection, index: Int) -> some View {
        let isCurrent = index == state.currentSectionIndex
        let isPast = index < state.currentSectionIndex

        return VStack(alignment: .leading, spacing: 8) {
            // Slide divider
            if index > 0 {
                HStack(spacing: 8) {
                    SlidePillView(slideNumber: section.slideNumber, colorHex: section.accentColorHex)
                    Rectangle()
                        .fill(Color(hex: section.accentColorHex)?.opacity(0.2) ?? Color.gray.opacity(0.2))
                        .frame(height: 1)
                }
                .padding(.top, 16)
                .padding(.bottom, 8)
            }

            Text(section.content)
                .font(.system(size: state.fontSize))
                .lineSpacing(state.fontSize * 0.5)
                .foregroundStyle(isCurrent ? .primary : (isPast ? .tertiary : .secondary))
                .opacity(isCurrent ? 1.0 : 0.5)
                .animation(.easeInOut(duration: 0.3), value: state.currentSectionIndex)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.bottom, 12)
    }

    // MARK: - Auto-scroll

    private func startAutoScroll() {
        stopAutoScroll()
        // Pixels per second based on speed multiplier
        let baseRate: Double = 30.0
        let interval: TimeInterval = 1.0 / 30.0 // 30 fps

        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in
            Task { @MainActor in
                guard state.isPlaying else { return }
                let pixelsPerFrame = (baseRate * state.scrollSpeed) * interval
                state.scrollOffset += pixelsPerFrame
            }
        }
    }

    private func stopAutoScroll() {
        timer?.invalidate()
        timer = nil
    }
}
