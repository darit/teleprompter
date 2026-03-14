// Teleprompter/Views/ScriptAssistant/ScriptPreviewPanel.swift
import SwiftUI

/// Value-type snapshot of a ScriptSection, breaking the SwiftData observation chain.
struct SectionSnapshot: Identifiable, Equatable {
    var id: Int { slideNumber }
    let slideNumber: Int
    let label: String
    let content: String
    let accentColorHex: String
    var thumbnailRelativePath: String = ""
}

/// Self-contained pulsing border that manages its own animation state.
private struct PulsingBorder: View {
    @State private var opacity: Double = 0.3

    var body: some View {
        RoundedRectangle(cornerRadius: 8)
            .stroke(Color.accentColor, lineWidth: 2)
            .opacity(opacity)
            .onAppear {
                withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                    opacity = 0.8
                }
            }
    }
}

struct ScriptPreviewPanel: View {
    var sections: [SectionSnapshot]
    var totalSlides: Int
    var targetDurationMinutes: Int?
    var activeSlideNumber: Int?
    var isStreaming: Bool = false
    var parallelGeneratingSlides: Set<Int> = []
    var isGeneratingAll: Bool = false
    @State private var showSlideImages: Bool = true
    var onGenerate: ((Int) -> Void)?
    var onGenerateAll: (() -> Void)?
    var onStopGenerateAll: (() -> Void)?

    private var sortedSections: [SectionSnapshot] {
        sections.sorted { $0.slideNumber < $1.slideNumber }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Script Preview")
                        .font(.system(size: 13, weight: .semibold))

                    if isGeneratingAll {
                        let done = totalSlides - parallelGeneratingSlides.count
                        Text("Generating \(done)/\(totalSlides)...")
                            .font(.system(size: 10))
                            .foregroundStyle(.orange)
                    } else if !sections.isEmpty {
                        Text("Live updating")
                            .font(.system(size: 10))
                            .foregroundStyle(.green)
                    }
                }

                Spacer()

                Toggle("Slides", isOn: $showSlideImages)
                    .toggleStyle(.switch)
                    .controlSize(.mini)

                if isGeneratingAll {
                    Button {
                        onStopGenerateAll?()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "stop.fill")
                                .font(.system(size: 8))
                            Text("Stop")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                } else if !isStreaming {
                    Button {
                        onGenerateAll?()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "bolt.fill")
                                .font(.system(size: 9))
                            Text("Generate All")
                                .font(.system(size: 11, weight: .medium))
                        }
                    }
                    .buttonStyle(.plain)
                    .help("Generate scripts for all slides in parallel")
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background {
                ZStack {
                    Rectangle().fill(.ultraThinMaterial)
                    VStack(spacing: 0) {
                        Rectangle()
                            .fill(.white.opacity(0.04))
                            .frame(height: 1)
                        Spacer()
                    }
                }
            }

            Divider()

            // Sections
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(sortedSections) { section in
                        previewSection(section)
                    }

                    let existingSlideNumbers = Set(sections.map(\.slideNumber))
                    ForEach(1...max(totalSlides, 1), id: \.self) { slideNum in
                        if !existingSlideNumbers.contains(slideNum) {
                            waitingSection(slideNumber: slideNum)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 20)
                .padding(.bottom, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Divider()

            // Progress bar
            progressBar
        }
    }

    private func previewSection(_ section: SectionSnapshot) -> some View {
        let isActive = activeSlideNumber == section.slideNumber
        let isParallelGenerating = parallelGeneratingSlides.contains(section.slideNumber)

        return VStack(alignment: .leading, spacing: 6) {
            // Slide thumbnail
            if showSlideImages && !section.thumbnailRelativePath.isEmpty {
                SlidePreviewThumbnail(relativePath: section.thumbnailRelativePath, maxWidth: 200)
                    .padding(.bottom, 4)
            }

            HStack(spacing: 6) {
                SlidePillView(slideNumber: section.slideNumber, colorHex: section.accentColorHex)
                let hasContent = !section.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                if isParallelGenerating {
                    ProgressView()
                        .scaleEffect(0.5)
                        .frame(width: 12, height: 12)
                } else if hasContent {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.green)
                }
                Spacer()

                if !isStreaming && !isGeneratingAll, let onGenerate {
                    Button {
                        onGenerate(section.slideNumber)
                    } label: {
                        Image(systemName: hasContent ? "arrow.counterclockwise" : "sparkles")
                            .font(.system(size: 10))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help(hasContent ? "Regenerate slide script" : "Generate slide script")
                }

                if hasContent {
                    Text(ReadTimeEstimator.formatDuration(
                        ReadTimeEstimator.estimateDuration(for: section.content)
                    ))
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                }
            }

            Text(StageDirectionRenderer.renderAttributedString(section.content))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
        }
        .overlay {
            if isActive || isParallelGenerating {
                PulsingBorder()
            }
        }
    }

    private func waitingSection(slideNumber: Int) -> some View {
        let isParallelGenerating = parallelGeneratingSlides.contains(slideNumber)

        return HStack(spacing: 6) {
            let accentColors = ["#4A9EFF", "#34C759", "#FF9500", "#FF2D55", "#AF52DE", "#5AC8FA", "#FFCC00", "#FF6B35"]
            SlidePillView(slideNumber: slideNumber, colorHex: accentColors[(slideNumber - 1) % accentColors.count])

            if isParallelGenerating {
                ProgressView()
                    .scaleEffect(0.5)
                    .frame(width: 12, height: 12)
                Text("Generating...")
                    .font(.system(size: 10))
                    .foregroundStyle(.orange)
            } else {
                Text("Waiting for context...")
                    .font(.system(size: 10))
                    .foregroundStyle(.quaternary)
            }
            Spacer()

            if !isStreaming && !isGeneratingAll, let onGenerate {
                Button {
                    onGenerate(slideNumber)
                } label: {
                    Image(systemName: "sparkles")
                        .font(.system(size: 10))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Generate slide script")
            }
        }
        .overlay {
            if isParallelGenerating {
                PulsingBorder()
            }
        }
    }

    private var progressBar: some View {
        HStack(spacing: 8) {
            let readyCount = sections.filter { !$0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count
            Text("\(readyCount) of \(totalSlides) slides ready")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)

            ProgressView(value: Double(readyCount), total: Double(max(totalSlides, 1)))
                .frame(width: 80)

            Spacer()

            let totalDuration = sortedSections.reduce(0.0) { total, section in
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
        .padding(.vertical, 8)
        .background {
            ZStack {
                Rectangle().fill(.ultraThinMaterial)
                VStack(spacing: 0) {
                    Spacer()
                    Rectangle()
                        .fill(.white.opacity(0.04))
                        .frame(height: 1)
                }
            }
        }
    }
}
