// Teleprompter/Views/ScriptAssistant/ScriptPreviewPanel.swift
import SwiftUI

struct ScriptPreviewPanel: View {
    let script: Script
    let totalSlides: Int
    let targetDurationMinutes: Int?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Script Preview")
                        .font(.system(size: 14, weight: .semibold))

                    if !script.sections.isEmpty {
                        Text("Live updating")
                            .font(.system(size: 10))
                            .foregroundStyle(.green)
                    }
                }

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial)

            Divider()

            // Sections
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    ForEach(script.sortedSections) { section in
                        previewSection(section)
                    }

                    // Show remaining slides as placeholders
                    let existingSlideNumbers = Set(script.sections.map(\.slideNumber))
                    ForEach(1...max(totalSlides, 1), id: \.self) { slideNum in
                        if !existingSlideNumbers.contains(slideNum) {
                            waitingSection(slideNumber: slideNum)
                        }
                    }
                }
                .padding(16)
            }

            Divider()

            // Progress bar
            progressBar
        }
    }

    private func previewSection(_ section: ScriptSection) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                SlidePillView(slideNumber: section.slideNumber, colorHex: section.accentColorHex)
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.green)
                Spacer()
                Text(ReadTimeEstimator.formatDuration(
                    ReadTimeEstimator.estimateDuration(for: section.content)
                ))
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
            }

            Text(section.content)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineSpacing(4)
        }
    }

    private func waitingSection(slideNumber: Int) -> some View {
        HStack(spacing: 6) {
            let accentColors = ["#4A9EFF", "#34C759", "#FF9500", "#FF2D55", "#AF52DE", "#5AC8FA", "#FFCC00", "#FF6B35"]
            SlidePillView(slideNumber: slideNumber, colorHex: accentColors[(slideNumber - 1) % accentColors.count])
            Text("Waiting for context...")
                .font(.system(size: 10))
                .foregroundStyle(.quaternary)
            Spacer()
        }
    }

    private var progressBar: some View {
        HStack(spacing: 8) {
            let readyCount = script.sections.count
            Text("\(readyCount) of \(totalSlides) slides ready")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)

            ProgressView(value: Double(readyCount), total: Double(max(totalSlides, 1)))
                .frame(width: 80)

            Spacer()

            let totalDuration = script.sortedSections.reduce(0.0) { total, section in
                total + ReadTimeEstimator.estimateDuration(for: section.content)
            }
            let durationText = ReadTimeEstimator.formatDuration(totalDuration)
            if let target = targetDurationMinutes {
                Text("\(durationText) / \(target) min target")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            } else {
                Text(durationText)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }
}
