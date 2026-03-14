// Teleprompter/Views/Components/SlidePreviewThumbnail.swift
import SwiftUI

struct SlidePreviewThumbnail: View {
    let relativePath: String
    var maxWidth: CGFloat = 160
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: maxWidth)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay {
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(.quaternary, lineWidth: 0.5)
                    }
            }
        }
        .task(id: relativePath) {
            image = await SlideImageStore.load(relativePath: relativePath)
        }
    }
}
