// Teleprompter/Views/Components/SlidePreviewThumbnail.swift
import SwiftUI

struct SlidePreviewThumbnail: View {
    let relativePath: String
    var maxWidth: CGFloat = 160
    @State private var image: NSImage?

    var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay {
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(.quaternary, lineWidth: 0.5)
                    }
            } else {
                // Placeholder while loading — gives the view a non-zero frame
                // so .task fires reliably
                RoundedRectangle(cornerRadius: 6)
                    .fill(.quaternary.opacity(0.3))
                    .aspectRatio(16/9, contentMode: .fit)
            }
        }
        .frame(maxWidth: maxWidth)
        .task(id: relativePath) {
            print("[SlideThumb] Loading: \(relativePath)")
            let loaded = await SlideImageStore.load(relativePath: relativePath)
            print("[SlideThumb] Result for \(relativePath): \(loaded != nil ? "OK \(Int(loaded!.size.width))x\(Int(loaded!.size.height))" : "nil")")
            image = loaded
        }
    }
}
