// Teleprompter/Services/SlideCardRenderer.swift
import SwiftUI

enum SlideCardRenderer {

    /// Render a content card for a single slide.
    /// Returns JPEG data of a 16:9 card showing title, body text, and first image.
    @MainActor
    static func render(slide: SlideContent) -> Data? {
        let cardView = SlideCardView(slide: slide)
        let size = NSSize(width: 480, height: 270)

        // Host in a temporary offscreen window so the view gets a proper
        // graphics context and layout pass. Plain NSHostingView without a
        // window can fail to render.
        let hostingView = NSHostingView(rootView: cardView)
        hostingView.frame = NSRect(origin: .zero, size: size)

        let offscreenWindow = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        offscreenWindow.contentView = hostingView
        offscreenWindow.orderBack(nil)
        offscreenWindow.setIsVisible(false)

        // Force full layout
        hostingView.layoutSubtreeIfNeeded()
        hostingView.display()

        guard let bitmap = hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds) else {
            offscreenWindow.contentView = nil
            return nil
        }
        hostingView.cacheDisplay(in: hostingView.bounds, to: bitmap)

        offscreenWindow.contentView = nil

        return bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.85])
    }

    /// Render content cards for all slides.
    @MainActor
    static func renderAll(slides: [SlideContent]) -> [(slideNumber: Int, data: Data)] {
        slides.compactMap { slide in
            guard let data = render(slide: slide) else { return nil }
            return (slide.slideNumber, data)
        }
    }
}

/// SwiftUI view that mimics a slide layout from parsed content.
/// 16:9 aspect ratio, dark background, title + bullets + optional image.
private struct SlideCardView: View {
    let slide: SlideContent

    private var bullets: [String] {
        slide.bodyText
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private var firstImage: NSImage? {
        slide.images.first.flatMap { NSImage(data: $0) }
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(
                    LinearGradient(
                        colors: [Color(white: 0.12), Color(white: 0.18)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            VStack(alignment: .leading, spacing: 0) {
                // Slide number badge
                HStack {
                    Text("SLIDE \(slide.slideNumber)")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.4))
                    Spacer()
                }
                .padding(.bottom, 8)

                // Title
                if !slide.title.isEmpty {
                    Text(slide.title)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .padding(.bottom, 12)
                }

                // Content area: text on left, image on right (if image exists)
                HStack(alignment: .top, spacing: 16) {
                    if !bullets.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(bullets.prefix(8), id: \.self) { bullet in
                                HStack(alignment: .top, spacing: 8) {
                                    Circle()
                                        .fill(.white.opacity(0.5))
                                        .frame(width: 5, height: 5)
                                        .padding(.top, 6)
                                    Text(bullet)
                                        .font(.system(size: 13))
                                        .foregroundStyle(.white.opacity(0.85))
                                        .lineLimit(2)
                                }
                            }
                            if bullets.count > 8 {
                                Text("+ \(bullets.count - 8) more...")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.white.opacity(0.4))
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    if let firstImage {
                        Image(nsImage: firstImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxWidth: 180, maxHeight: 120)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                }

                Spacer(minLength: 0)

                // Notes indicator
                if !slide.notes.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "note.text")
                            .font(.system(size: 9))
                        Text("Has speaker notes")
                            .font(.system(size: 9))
                    }
                    .foregroundStyle(.white.opacity(0.3))
                }
            }
            .padding(20)
        }
        .frame(width: 480, height: 270)  // 16:9
    }
}
