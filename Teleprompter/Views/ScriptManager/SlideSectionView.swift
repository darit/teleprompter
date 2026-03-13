// Teleprompter/Views/ScriptManager/SlideSectionView.swift
import SwiftUI

struct SlideSectionView: View {
    @Bindable var section: ScriptSection
    var fontSize: Double = 13
    @State private var isEditing = false
    @FocusState private var editorFocused: Bool

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

                if isEditing {
                    Button("Done") {
                        commitEdit()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                }

                Text(ReadTimeEstimator.formatDuration(
                    ReadTimeEstimator.estimateDuration(for: section.content)
                ))
                .font(.system(size: 9))
                .foregroundStyle(.quaternary)
            }

            if isEditing {
                TextEditor(text: $section.content)
                    .font(.system(size: fontSize))
                    .foregroundStyle(.secondary)
                    .lineSpacing(6)
                    .scrollContentBackground(.hidden)
                    .padding(.leading, 4)
                    .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
                    .focused($editorFocused)
                    .onChange(of: editorFocused) { _, focused in
                        if !focused {
                            commitEdit()
                        }
                    }
                    .onKeyPress(.escape) {
                        commitEdit()
                        return .handled
                    }
            } else {
                Text(StageDirectionRenderer.renderAttributedString(section.content))
                    .font(.system(size: fontSize))
                    .foregroundStyle(.secondary)
                    .lineSpacing(6)
                    .padding(.leading, 4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        isEditing = true
                        editorFocused = true
                    }
            }
        }
    }

    private func commitEdit() {
        isEditing = false
        editorFocused = false
    }
}

#Preview {
    SlideSectionView(section: PreviewSampleData.sampleSections[2])
        .padding()
}
