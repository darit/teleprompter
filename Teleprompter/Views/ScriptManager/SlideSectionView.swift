// Teleprompter/Views/ScriptManager/SlideSectionView.swift
import SwiftUI

struct SlideSectionView: View {
    @Bindable var section: ScriptSection
    var fontSize: Double = 13

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

            TextEditor(text: $section.content)
                .font(.system(size: fontSize))
                .foregroundStyle(.secondary)
                .lineSpacing(6)
                .scrollContentBackground(.hidden)
                .padding(.leading, 4)
                .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
        }
    }
}

#Preview {
    SlideSectionView(section: PreviewSampleData.sampleSections[2])
        .padding()
}
