// Teleprompter/Views/ScriptManager/ScriptDetailView.swift
import SwiftUI
import SwiftData

struct ScriptDetailView: View {
    @Bindable var script: Script
    @State private var isEditingName = false
    var onRefineWithAI: () -> Void = {}
    var onPresent: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    if isEditingName {
                        TextField("Script name", text: $script.name)
                            .font(.system(size: 22, weight: .bold))
                            .textFieldStyle(.plain)
                            .onSubmit {
                                isEditingName = false
                                script.modifiedAt = .now
                            }
                    } else {
                        Text(script.name)
                            .font(.system(size: 22, weight: .bold))
                            .onTapGesture { isEditingName = true }
                    }

                    HStack(spacing: 8) {
                        Text("\(script.sections.count) slides")
                        Text("--")
                            .foregroundStyle(.quaternary)
                        Text("Modified \(script.modifiedAt, style: .relative)")
                        Text("--")
                            .foregroundStyle(.quaternary)
                        Text(ReadTimeEstimator.formatDuration(totalDuration))
                    }
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                }

                Spacer()

                HStack(spacing: 8) {
                    Button("Refine with AI") {
                        onRefineWithAI()
                    }
                    .buttonStyle(.glass)

                    Button("Present") {
                        onPresent()
                    }
                    .buttonStyle(.glass)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 20)

            Divider()

            // Script sections
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 22) {
                    ForEach(Array(script.sortedSections.enumerated()), id: \.element.id) { index, section in
                        if index > 0 {
                            Divider().padding(.vertical, 4)
                        }
                        SlideSectionView(section: section, fontSize: script.fontSize)
                    }

                    if script.sections.isEmpty {
                        ContentUnavailableView(
                            "No script content",
                            systemImage: "doc.text",
                            description: Text("Create sections manually or import a PPTX to generate a script with AI.")
                        )
                    }
                }
                .padding(24)
            }

            Divider()

            // Bottom bar
            HStack {
                HStack(spacing: 12) {
                    Text("\(script.sections.count) slides")
                    Text("|").foregroundStyle(.quaternary)
                    Text(ReadTimeEstimator.formatDuration(totalDuration) + " total")
                    Text("|").foregroundStyle(.quaternary)
                    Text("Speed: \(String(format: "%.1f", script.scrollSpeed))x")
                }

                Spacer()

                HStack(spacing: 8) {
                    Text("Font \(Int(script.fontSize))pt")
                    Button { adjustFontSize(-1) } label: {
                        Text("A-").font(.system(size: 10))
                    }
                    .buttonStyle(.glass)

                    Button { adjustFontSize(1) } label: {
                        Text("A+").font(.system(size: 10))
                    }
                    .buttonStyle(.glass)
                }
            }
            .font(.system(size: 10))
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 24)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial)
        }
    }

    private var totalDuration: TimeInterval {
        script.sortedSections.reduce(0) { total, section in
            total + ReadTimeEstimator.estimateDuration(for: section.content)
        }
    }

    private func adjustFontSize(_ delta: Double) {
        script.fontSize = max(12, min(32, script.fontSize + delta))
        script.modifiedAt = .now
    }
}

#Preview {
    ScriptDetailView(script: PreviewSampleData.sampleScript(), onRefineWithAI: {}, onPresent: {})
        .modelContainer(PreviewSampleData.container)
        .frame(width: 700, height: 500)
}
