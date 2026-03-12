// Teleprompter/Views/Components/SlidePillView.swift
import SwiftUI

struct SlidePillView: View {
    let slideNumber: Int
    let colorHex: String

    var body: some View {
        Text("SLIDE \(slideNumber)")
            .font(.system(size: 9, weight: .bold))
            .kerning(0.5)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 3)
            .background {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(hex: colorHex)?.opacity(0.12) ?? Color.gray.opacity(0.12))
                    .overlay {
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color(hex: colorHex)?.opacity(0.2) ?? Color.gray.opacity(0.2), lineWidth: 1)
                    }
            }
        // TODO: Add .glassEffect(.regular.interactive, in: .capsule) when targeting macOS Tahoe
    }
}

#Preview {
    HStack(spacing: 8) {
        SlidePillView(slideNumber: 1, colorHex: "#4A9EFF")
        SlidePillView(slideNumber: 2, colorHex: "#34C759")
        SlidePillView(slideNumber: 3, colorHex: "#FF9500")
    }
    .padding()
}
