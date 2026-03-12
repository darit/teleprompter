// Teleprompter/Views/ScriptManager/SlideSectionView.swift
import SwiftUI

struct SlideSectionView: View {
    let section: ScriptSection

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                SlidePillView(slideNumber: section.slideNumber, colorHex: section.accentColorHex)

                if section.isAIRefined {
                    Text("AI refined")
                        .font(.system(size: 8))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(.quaternary)
                        }
                }

                Spacer()

                Text(ReadTimeEstimator.formatDuration(
                    ReadTimeEstimator.estimateDuration(for: section.content)
                ))
                .font(.system(size: 9))
                .foregroundStyle(.quaternary)
            }

            Text(section.content)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .lineSpacing(6)
                .padding(.leading, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

#Preview {
    SlideSectionView(section: PreviewSampleData.sampleSections[2])
        .padding()
}
