// Teleprompter/Views/ScriptManager/SlideSectionView.swift
import SwiftUI

struct SlideSectionView: View {
    @Bindable var section: ScriptSection
    var fontSize: Double = 13
    @State private var isEditing = false
    @FocusState private var editorFocused: Bool

    /// Stage directions available for insertion
    private static let stageDirections: [(label: String, marker: String, icon: String)] = [
        ("Pause", "[PAUSE]", "pause.fill"),
        ("Slow", "[SLOW]", "tortoise.fill"),
        ("Camera", "[LOOK AT CAMERA]", "eye.fill"),
        ("Show Slide", "[SHOW SLIDE]", "rectangle.on.rectangle.angled"),
        ("Breathe", "[BREATHE]", "wind"),
    ]

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
                // Stage direction toolbar
                stageDirectionToolbar

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

    private var stageDirectionToolbar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                Text("Insert:")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.tertiary)

                ForEach(Self.stageDirections, id: \.marker) { direction in
                    Button {
                        insertDirection(direction.marker)
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: direction.icon)
                                .font(.system(size: 9))
                            Text(direction.label)
                                .font(.system(size: 9, weight: .medium))
                        }
                        .foregroundStyle(.yellow.opacity(0.9))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(.yellow.opacity(0.1))
                                .strokeBorder(.yellow.opacity(0.2), lineWidth: 0.5)
                        }
                    }
                    .buttonStyle(.plain)
                }

                Divider().frame(height: 14)

                // Common punctuation helpers
                Button {
                    insertDirection("...")
                } label: {
                    Text("...")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(.secondary.opacity(0.08))
                        }
                }
                .buttonStyle(.plain)
                .help("Ellipsis — thinking pause")

                Button {
                    insertDirection(" -- ")
                } label: {
                    Text("--")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(.secondary.opacity(0.08))
                        }
                }
                .buttonStyle(.plain)
                .help("Em dash — brief structural pause")
            }
            .padding(.horizontal, 4)
        }
        .padding(.vertical, 4)
        .background {
            RoundedRectangle(cornerRadius: 6)
                .fill(.ultraThinMaterial)
        }
    }

    private func insertDirection(_ marker: String) {
        // Append marker at the end with a space separator
        let trimmed = section.content.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            section.content = marker
        } else {
            // Add space before marker if content doesn't end with whitespace
            let needsSpace = !section.content.hasSuffix(" ") && !section.content.hasSuffix("\n")
            section.content += (needsSpace ? " " : "") + marker + " "
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
