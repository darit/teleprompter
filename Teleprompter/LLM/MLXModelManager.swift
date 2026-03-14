// Teleprompter/LLM/MLXModelManager.swift
import Foundation
import MLXLLM
import MLX
import MLXLMCommon

@Observable
final class MLXModelManager {
    static let shared = MLXModelManager()

    // MARK: - State (read from main thread)

    @MainActor var availableModels: [MLXModelInfo] = []
    @MainActor var selectedModel: MLXModelInfo?
    @MainActor var loadState: LoadState = .unloaded
    @MainActor var downloadProgress: DownloadProgress?

    enum LoadState: Equatable {
        case unloaded
        case loading(progress: Double)
        case loaded
        case error(String)
    }

    struct DownloadProgress: Equatable {
        let modelId: String
        var progress: Double
        var downloadedBytes: UInt64
        var totalBytes: UInt64
    }

    // MARK: - Internal

    private(set) var modelContainer: ModelContainer?
    private(set) var modelConfiguration: ModelConfiguration?
    private var downloadTask: Task<Void, Never>?
    private var memoryPressureSource: DispatchSourceMemoryPressure?

    /// Cached system RAM — doesn't change at runtime.
    let systemRAM: UInt64 = ProcessInfo.processInfo.physicalMemory

    /// Hugging Face cache directory.
    private static let hfCacheURL: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".cache/huggingface/hub")

    /// LM Studio models directory (read from settings.json or default).
    private static let lmStudioModelsURL: URL = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let settingsFile = home.appendingPathComponent(".lmstudio/settings.json")
        if let data = try? Data(contentsOf: settingsFile),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let folder = json["downloadsFolder"] as? String {
            return URL(fileURLWithPath: folder)
        }
        return home.appendingPathComponent(".lmstudio/models")
    }()

    init() {
        setupMemoryPressureObserver()
        // Eagerly restore selected model so it's available before Settings is opened.
        Task { @MainActor in
            scanForModels()
        }
    }

    deinit {
        downloadTask?.cancel()
        memoryPressureSource?.cancel()
    }

    // MARK: - Memory Pressure (macOS — NOT iOS notification)

    private func setupMemoryPressureObserver() {
        let source = DispatchSource.makeMemoryPressureSource(
            eventMask: [.warning, .critical],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            self?.unloadModel()
        }
        source.resume()
        memoryPressureSource = source
    }

    // MARK: - Model Discovery (runs on background thread)

    @MainActor
    func scanForModels() {
        Task.detached { [weak self] in
            let discovered = await self?.performScan() ?? []
            await MainActor.run {
                guard let self else { return }

                // Merge: prefer discovered (local) models over recommended entries
                let discoveredByRepo = Dictionary(
                    discovered.map { ($0.repoId, $0) },
                    uniquingKeysWith: { first, _ in first }
                )
                var merged: [MLXModelInfo] = MLXModelInfo.recommended.map { rec in
                    // If a local copy exists, use it (preserves localPath + source)
                    discoveredByRepo[rec.repoId] ?? rec
                }
                // Add any discovered models not in the recommended list
                for model in discovered {
                    if !merged.contains(where: { $0.repoId == model.repoId }) {
                        merged.append(model)
                    }
                }
                self.availableModels = merged

                // Restore selected model from settings
                let savedId = AppSettings.shared.mlxSelectedModelId
                if !savedId.isEmpty {
                    self.selectedModel = merged.first { $0.repoId == savedId }
                }
            }
        }
    }

    private func performScan() -> [MLXModelInfo] {
        var discovered = scanHuggingFaceCache(at: Self.hfCacheURL)
        discovered += scanLMStudioModels(at: Self.lmStudioModelsURL)
        discovered += scanBookmarkedModels()
        return discovered
    }

    /// Scan user-bookmarked local model folders (for sandbox support).
    private func scanBookmarkedModels() -> [MLXModelInfo] {
        var models: [MLXModelInfo] = []
        for (path, bookmarkData) in AppSettings.shared.mlxLocalModelBookmarks {
            var isStale = false
            guard let url = try? URL(
                resolvingBookmarkData: bookmarkData,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ) else { continue }

            guard url.startAccessingSecurityScopedResource() else { continue }
            defer { url.stopAccessingSecurityScopedResource() }

            let configFile = url.appendingPathComponent("config.json")
            guard FileManager.default.fileExists(atPath: configFile.path) else { continue }
            guard let files = try? FileManager.default.contentsOfDirectory(atPath: url.path),
                  files.contains(where: { $0.hasSuffix(".safetensors") }) else { continue }

            let folderName = url.lastPathComponent
            let parentName = url.deletingLastPathComponent().lastPathComponent
            let repoId = "\(parentName)/\(folderName)"

            // Skip if already discovered from LM Studio or HF
            if models.contains(where: { $0.localPath == path }) { continue }

            models.append(MLXModelInfo(
                repoId: repoId,
                name: folderName,
                parameterCount: inferParamCount(from: folderName),
                quantization: inferQuant(from: folderName),
                sizeOnDisk: directorySize(at: url),
                supportsVision: false,
                minimumRAM: 0,
                source: .local,
                localPath: path
            ))
        }
        return models
    }

    /// Check if a model's files are already available locally.
    func isDownloaded(_ model: MLXModelInfo) -> Bool {
        if let localPath = model.localPath {
            return FileManager.default.fileExists(atPath: localPath)
        }
        return FileManager.default.fileExists(atPath: Self.modelCacheDir(for: model.repoId).path)
    }

    // MARK: - Download

    @MainActor
    func downloadModel(_ model: MLXModelInfo) {
        downloadTask?.cancel()

        downloadProgress = DownloadProgress(
            modelId: model.repoId, progress: 0,
            downloadedBytes: 0, totalBytes: model.sizeOnDisk
        )

        downloadTask = Task {
            do {
                let config = ModelConfiguration(id: model.repoId)

                let container = try await LLMModelFactory.shared.loadContainer(
                    configuration: config
                ) { progress in
                    Task { @MainActor in
                        self.downloadProgress?.progress = progress.fractionCompleted
                        self.downloadProgress?.downloadedBytes = UInt64(
                            Double(model.sizeOnDisk) * progress.fractionCompleted
                        )
                    }
                }
                _ = container  // trigger download

                await MainActor.run {
                    self.downloadProgress = nil
                    self.scanForModels()
                }
            } catch {
                await MainActor.run {
                    self.downloadProgress = nil
                    self.loadState = .error("Download failed: \(error.localizedDescription)")
                }
            }
        }
    }

    @MainActor
    func cancelDownload() {
        downloadTask?.cancel()
        downloadTask = nil
        downloadProgress = nil
    }

    // MARK: - Load / Unload

    @MainActor
    func loadModel(_ model: MLXModelInfo) async throws {
        unloadModel()

        loadState = .loading(progress: 0)
        selectedModel = model
        AppSettings.shared.mlxSelectedModelId = model.repoId

        let config: ModelConfiguration
        if let localPath = model.localPath {
            config = ModelConfiguration(directory: URL(fileURLWithPath: localPath))
        } else {
            config = ModelConfiguration(id: model.repoId)
        }
        modelConfiguration = config

        do {
            let container = try await LLMModelFactory.shared.loadContainer(
                configuration: config
            ) { progress in
                Task { @MainActor in
                    self.loadState = .loading(progress: progress.fractionCompleted)
                }
            }

            modelContainer = container
            loadState = .loaded
        } catch {
            loadState = .error("Failed to load: \(error.localizedDescription)")
            modelConfiguration = nil
            throw error
        }
    }

    @MainActor
    func unloadModel() {
        modelContainer = nil
        modelConfiguration = nil
        Memory.clearCache()
        loadState = .unloaded
    }

    // MARK: - Delete

    @MainActor
    func deleteModel(_ model: MLXModelInfo) {
        // Unload if this is the active model
        if selectedModel?.repoId == model.repoId {
            unloadModel()
            selectedModel = nil
            AppSettings.shared.mlxSelectedModelId = ""
        }

        // Only delete from HF cache — don't delete LM Studio or other external models
        if model.source != .lmStudio && model.localPath == nil {
            try? FileManager.default.removeItem(at: Self.modelCacheDir(for: model.repoId))
        }
        scanForModels()
    }

    // MARK: - Memory

    var systemRAMDescription: String {
        Self.formatBytes(systemRAM)
    }

    func canFitInRAM(_ model: MLXModelInfo) -> Bool {
        model.minimumRAM <= systemRAM
    }

    // MARK: - Formatting

    static func formatBytes(_ bytes: UInt64) -> String {
        let gb = Double(bytes) / 1_073_741_824
        if gb >= 1.0 {
            return String(format: "%.1f GB", gb)
        }
        let mb = Double(bytes) / 1_048_576
        return String(format: "%.0f MB", mb)
    }

    // MARK: - Validation

    /// Quick check that a HF repo looks like an MLX model.
    static func validateMLXRepo(repoId: String) async -> Bool {
        guard let configURL = URL(string: "https://huggingface.co/\(repoId)/resolve/main/config.json") else {
            return false
        }
        guard let (data, _) = try? await URLSession.shared.data(from: configURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              json["model_type"] != nil else {
            return false
        }
        guard let weightURL = URL(string: "https://huggingface.co/api/models/\(repoId)") else {
            return false
        }
        guard let (apiData, _) = try? await URLSession.shared.data(from: weightURL),
              let apiJson = try? JSONSerialization.jsonObject(with: apiData) as? [String: Any],
              let siblings = apiJson["siblings"] as? [[String: Any]] else {
            return false
        }
        return siblings.contains { ($0["rfilename"] as? String)?.hasSuffix(".safetensors") ?? false }
    }

    // MARK: - Private Helpers

    /// Returns the HF cache directory for a given repo ID.
    private static func modelCacheDir(for repoId: String) -> URL {
        hfCacheURL.appendingPathComponent(
            "models--\(repoId.replacingOccurrences(of: "/", with: "--"))"
        )
    }

    private func scanHuggingFaceCache(at url: URL) -> [MLXModelInfo] {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: url, includingPropertiesForKeys: [.isDirectoryKey]
        ) else { return [] }

        var models: [MLXModelInfo] = []
        for dir in contents where dir.lastPathComponent.hasPrefix("models--") {
            let name = dir.lastPathComponent
                .replacingOccurrences(of: "models--", with: "")
                .replacingOccurrences(of: "--", with: "/")

            // Only include MLX models
            guard name.lowercased().contains("mlx") else { continue }

            // Verify it's a valid model (has config.json in a snapshot)
            let snapshots = dir.appendingPathComponent("snapshots")
            guard let snapshotDirs = try? FileManager.default.contentsOfDirectory(
                at: snapshots, includingPropertiesForKeys: [.contentModificationDateKey]
            ) else { continue }

            let sorted = snapshotDirs.sorted {
                let d1 = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
                let d2 = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
                return d1 > d2
            }
            guard let latest = sorted.first else { continue }

            let configFile = latest.appendingPathComponent("config.json")
            guard FileManager.default.fileExists(atPath: configFile.path) else { continue }

            let size = directorySize(at: dir)

            models.append(MLXModelInfo(
                repoId: name,
                name: name.components(separatedBy: "/").last ?? name,
                parameterCount: "?",
                quantization: name.contains("4bit") ? "4-bit" : (name.contains("8bit") ? "8-bit" : "?"),
                sizeOnDisk: size,
                supportsVision: false,
                minimumRAM: size * 2,
                source: .huggingFace
            ))
        }
        return models
    }

    /// Scan LM Studio's models directory for MLX-compatible models.
    /// LM Studio stores models as: ~/.lmstudio/models/{org}/{model-name}/
    private func scanLMStudioModels(at baseURL: URL) -> [MLXModelInfo] {
        guard let orgs = try? FileManager.default.contentsOfDirectory(
            at: baseURL, includingPropertiesForKeys: [.isDirectoryKey]
        ) else { return [] }

        var models: [MLXModelInfo] = []
        for orgDir in orgs {
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: orgDir.path, isDirectory: &isDir),
                  isDir.boolValue else { continue }

            let orgName = orgDir.lastPathComponent
            guard let modelDirs = try? FileManager.default.contentsOfDirectory(
                at: orgDir, includingPropertiesForKeys: [.isDirectoryKey]
            ) else { continue }

            for modelDir in modelDirs {
                var isModelDir: ObjCBool = false
                guard FileManager.default.fileExists(atPath: modelDir.path, isDirectory: &isModelDir),
                      isModelDir.boolValue else { continue }

                // Must have config.json (valid model) and .safetensors files (MLX-compatible)
                let configFile = modelDir.appendingPathComponent("config.json")
                guard FileManager.default.fileExists(atPath: configFile.path) else { continue }

                // Check for safetensors files (MLX format)
                guard let files = try? FileManager.default.contentsOfDirectory(atPath: modelDir.path) else { continue }
                let hasSafetensors = files.contains { $0.hasSuffix(".safetensors") }
                guard hasSafetensors else { continue }

                // Skip GGUF-only models
                let hasGGUF = files.contains { $0.hasSuffix(".gguf") }
                if hasGGUF && !hasSafetensors { continue }

                let modelName = modelDir.lastPathComponent
                let repoId = "\(orgName)/\(modelName)"
                let size = directorySize(at: modelDir)

                models.append(MLXModelInfo(
                    repoId: repoId,
                    name: modelName,
                    parameterCount: inferParamCount(from: modelName),
                    quantization: inferQuant(from: modelName),
                    sizeOnDisk: size,
                    supportsVision: false,
                    minimumRAM: size * 2,
                    source: .lmStudio,
                    localPath: modelDir.path
                ))
            }
        }
        return models
    }

    func inferParamCount(from name: String) -> String {
        let patterns = ["1B", "3B", "4B", "7B", "8B", "13B", "14B", "24B", "70B"]
        let upper = name.uppercased()
        for p in patterns.reversed() {
            if upper.contains(p) || upper.contains("-\(p)") { return p }
        }
        return "?"
    }

    func inferQuant(from name: String) -> String {
        let lower = name.lowercased()
        if lower.contains("4bit") || lower.contains("4-bit") || lower.contains("q4") { return "4-bit" }
        if lower.contains("6bit") || lower.contains("6-bit") || lower.contains("q6") { return "6-bit" }
        if lower.contains("8bit") || lower.contains("8-bit") || lower.contains("q8") { return "8-bit" }
        if lower.contains("bf16") || lower.contains("fp16") { return "fp16" }
        return "?"
    }

    private func directorySize(at url: URL) -> UInt64 {
        guard let enumerator = FileManager.default.enumerator(
            at: url, includingPropertiesForKeys: [.fileSizeKey]
        ) else { return 0 }
        var total: UInt64 = 0
        for case let file as URL in enumerator {
            total += UInt64((try? file.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
        }
        return total
    }
}
