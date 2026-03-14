// Teleprompter/Views/Settings/ModelManagerView.swift
import SwiftUI

struct ModelManagerView: View {
    private var manager: MLXModelManager { .shared }
    private var settings: AppSettings { .shared }
    @State private var customRepoId = ""
    @State private var isValidating = false
    @State private var validationError: String?
    @State private var confirmDelete: MLXModelInfo?

    var body: some View {
        Form {
            Section {
                HStack {
                    Text("System RAM")
                    Spacer()
                    Text(manager.systemRAMDescription)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("System")
            }

            recommendedSection

            allModelsSection

            customModelSection

            generationSettingsSection

            if let progress = manager.downloadProgress {
                downloadProgressSection(progress)
            }
        }
        .formStyle(.grouped)
        .padding(.top, 8)
        .onAppear {
            manager.scanForModels()
        }
        .alert("Delete Model?", isPresented: .init(
            get: { confirmDelete != nil },
            set: { if !$0 { confirmDelete = nil } }
        )) {
            Button("Cancel", role: .cancel) { confirmDelete = nil }
            Button("Delete", role: .destructive) {
                if let model = confirmDelete {
                    manager.deleteModel(model)
                }
                confirmDelete = nil
            }
        } message: {
            if let model = confirmDelete {
                Text("Remove \(model.name) from disk? This will free \(MLXModelManager.formatBytes(model.sizeOnDisk)).")
            }
        }
    }

    // MARK: - Recommended

    private var recommendedSection: some View {
        Section {
            let best = MLXModelInfo.bestForThisMachine
            ModelRow(
                model: best,
                isSelected: manager.selectedModel?.repoId == best.repoId,
                isDownloaded: manager.isDownloaded(best),
                canFit: manager.canFitInRAM(best),
                loadState: manager.loadState,
                onDownload: { manager.downloadModel(best) },
                onSelect: { Task { try? await manager.loadModel(best) } },
                onDelete: { confirmDelete = best }
            )
        } header: {
            Label("Recommended for Your Mac", systemImage: "star.fill")
        }
    }

    // MARK: - All Models

    private var allModelsSection: some View {
        Section("All Models") {
            ForEach(manager.availableModels) { model in
                ModelRow(
                    model: model,
                    isSelected: manager.selectedModel?.repoId == model.repoId,
                    isDownloaded: manager.isDownloaded(model),
                    canFit: manager.canFitInRAM(model),
                    loadState: manager.loadState,
                    onDownload: { manager.downloadModel(model) },
                    onSelect: { Task { try? await manager.loadModel(model) } },
                    onDelete: { confirmDelete = model }
                )
            }
        }
    }

    // MARK: - Custom Model

    private var customModelSection: some View {
        Section {
            HStack {
                TextField("mlx-community/...", text: $customRepoId)
                    .textFieldStyle(.roundedBorder)

                Button("Get") {
                    validateAndDownloadCustom()
                }
                .disabled(customRepoId.isEmpty || isValidating)
            }

            if isValidating {
                HStack {
                    ProgressView()
                        .controlSize(.small)
                    Text("Validating model...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let error = validationError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Text("Only MLX-format models (from mlx-community) are supported.")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)

            Divider()

            Button("Add Local Model Folder...") {
                addLocalModelFolder()
            }

            Text("Point to a folder containing a model with config.json and .safetensors files (e.g. from LM Studio).")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        } header: {
            Text("Custom Model")
        }
    }

    // MARK: - Generation Settings

    private var generationSettingsSection: some View {
        Section("Generation Settings") {
            HStack {
                Text("Temperature")
                Spacer()
                Slider(value: .init(
                    get: { settings.mlxTemperature },
                    set: { settings.mlxTemperature = $0 }
                ), in: 0.0...2.0, step: 0.1)
                    .frame(width: 160)
                Text(String(format: "%.1f", settings.mlxTemperature))
                    .foregroundStyle(.secondary)
                    .frame(width: 30, alignment: .trailing)
            }

            HStack {
                Text("Top-P")
                Spacer()
                Slider(value: .init(
                    get: { settings.mlxTopP },
                    set: { settings.mlxTopP = $0 }
                ), in: 0.0...1.0, step: 0.05)
                    .frame(width: 160)
                Text(String(format: "%.2f", settings.mlxTopP))
                    .foregroundStyle(.secondary)
                    .frame(width: 35, alignment: .trailing)
            }

            HStack {
                Text("Max Tokens")
                Spacer()
                Picker("", selection: .init(
                    get: { settings.mlxMaxTokens },
                    set: { settings.mlxMaxTokens = $0 }
                )) {
                    Text("1024").tag(1024)
                    Text("2048").tag(2048)
                    Text("4096").tag(4096)
                    Text("8192").tag(8192)
                }
                .pickerStyle(.menu)
                .frame(width: 100)
            }
        }
    }

    // MARK: - Download Progress

    private func downloadProgressSection(_ progress: MLXModelManager.DownloadProgress) -> some View {
        Section("Download Progress") {
            VStack(alignment: .leading, spacing: 6) {
                Text("Downloading \(progress.modelId)...")
                    .font(.caption)

                ProgressView(value: progress.progress)

                HStack {
                    Text("\(MLXModelManager.formatBytes(progress.downloadedBytes)) / \(MLXModelManager.formatBytes(progress.totalBytes))")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Spacer()

                    Text("\(Int(progress.progress * 100))%")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Button("Cancel") {
                        manager.cancelDownload()
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.red)
                    .font(.caption)
                }
            }
        }
    }

    // MARK: - Helpers

    private func addLocalModelFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = "Select a folder containing an MLX model (config.json + .safetensors)"
        panel.prompt = "Add Model"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        // Verify it's a valid MLX model directory
        let configFile = url.appendingPathComponent("config.json")
        guard FileManager.default.fileExists(atPath: configFile.path) else {
            validationError = "No config.json found in this folder."
            return
        }
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: url.path),
              files.contains(where: { $0.hasSuffix(".safetensors") }) else {
            validationError = "No .safetensors files found. This may be a GGUF model (not supported by MLX)."
            return
        }

        // Bookmark the URL for sandbox persistence
        if let bookmark = try? url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) {
            var bookmarks = AppSettings.shared.mlxLocalModelBookmarks
            bookmarks[url.path] = bookmark
            AppSettings.shared.mlxLocalModelBookmarks = bookmarks
        }

        let folderName = url.lastPathComponent
        let parentName = url.deletingLastPathComponent().lastPathComponent

        let model = MLXModelInfo(
            repoId: "\(parentName)/\(folderName)",
            name: folderName,
            parameterCount: MLXModelManager.shared.inferParamCount(from: folderName),
            quantization: MLXModelManager.shared.inferQuant(from: folderName),
            sizeOnDisk: 0,
            supportsVision: false,
            minimumRAM: 0,
            source: .local,
            localPath: url.path
        )

        Task { try? await MLXModelManager.shared.loadModel(model) }
    }

    private func validateAndDownloadCustom() {
        let repoId = customRepoId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !repoId.isEmpty else { return }

        isValidating = true
        validationError = nil

        Task {
            let valid = await MLXModelManager.validateMLXRepo(repoId: repoId)
            await MainActor.run {
                isValidating = false
                if valid {
                    let custom = MLXModelInfo(
                        repoId: repoId,
                        name: repoId.components(separatedBy: "/").last ?? repoId,
                        parameterCount: "?",
                        quantization: "?",
                        sizeOnDisk: 0,
                        supportsVision: false,
                        minimumRAM: 0,
                        source: .huggingFace
                    )
                    manager.downloadModel(custom)
                    customRepoId = ""
                } else {
                    validationError = "Not a valid MLX model. Check the repo ID and ensure it has .safetensors files."
                }
            }
        }
    }
}

// MARK: - Model Row

private struct ModelRow: View {
    let model: MLXModelInfo
    let isSelected: Bool
    let isDownloaded: Bool
    let canFit: Bool
    let loadState: MLXModelManager.LoadState
    let onDownload: () -> Void
    let onSelect: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(model.name)
                        .font(.system(size: 12, weight: isSelected ? .semibold : .regular))

                    if model.source == .lmStudio {
                        Text("LM Studio")
                            .font(.system(size: 9, weight: .medium))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(.blue.opacity(0.15))
                            .foregroundStyle(.blue)
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                    }

                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.system(size: 11))
                    }
                }

                HStack(spacing: 8) {
                    Text(model.parameterCount)
                    Text(model.quantization)
                    Text(MLXModelManager.formatBytes(model.sizeOnDisk))
                    ramIndicator
                }
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            }

            Spacer()

            if isDownloaded {
                if isSelected {
                    if case .loading(let progress) = loadState {
                        ProgressView(value: progress)
                            .frame(width: 60)
                    } else {
                        Text("Active")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                } else {
                    HStack(spacing: 8) {
                        Button("Select") { onSelect() }
                            .buttonStyle(.plain)
                            .font(.caption)
                            .foregroundStyle(.tint)

                        // Don't show delete for LM Studio models — they belong to LM Studio
                        if model.source != .lmStudio {
                            Button(role: .destructive) { onDelete() } label: {
                                Image(systemName: "trash")
                                    .font(.system(size: 10))
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.red.opacity(0.7))
                        }
                    }
                }
            } else {
                Button("Download") { onDownload() }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(.tint)
                    .disabled(!canFit)
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var ramIndicator: some View {
        let gb = Int(Double(model.minimumRAM) / 1_073_741_824)
        if canFit {
            Label("\(gb)GB", systemImage: "checkmark")
                .foregroundStyle(.green)
        } else {
            Label("\(gb)GB", systemImage: "exclamationmark.triangle")
                .foregroundStyle(.orange)
        }
    }
}
