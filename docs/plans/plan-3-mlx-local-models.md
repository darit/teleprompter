# Plan 3: MLX Local Model Support

**Priority:** 3 (biggest lift, most strategic)
**Estimated effort:** 5-8 sessions across 4 phases
**Risk:** Medium (SPM complexity, memory management, model compatibility)
**Depends on:** Plan 1 (for `PersistenceManager.appSupportDirectory`) — or use inline fallback

## Problem

The app currently depends on either:
- **LM Studio** — requires a separate app running with a model loaded
- **Claude Code CLI** — requires npm, an Anthropic API key, and internet

For commercialization as a standalone Mac app, we need a zero-dependency local LLM option. Users should be able to download a model and generate scripts without any external tools.

## Goal

Two new LLM providers:
1. **Apple Foundation Models** — zero-config, built into macOS 26+, works instantly
2. **MLX Swift** — run any Hugging Face model locally on Apple Silicon, with a model manager UI

---

## Architecture Overview

```
LLMProvider (protocol)
├── ClaudeCLIProvider        (existing — wraps CLI binary)
├── LMStudioProvider         (existing — HTTP to local server)
├── FoundationModelProvider  (NEW — Apple's on-device model, Phase 1)
└── MLXProvider              (NEW — runs HF models via mlx-swift, Phase 2)

MLXModelManager (singleton)
├── Scans local directories for models
├── Downloads from Hugging Face Hub
├── Loads/unloads models (memory management)
└── Provides recommended model list

ProviderChoice (enum)
├── .foundationModel  "Apple On-Device"     (NEW)
├── .mlxLocal         "Local Model (MLX)"   (NEW)
├── .claudeCLI        "Claude Code CLI"
└── .lmStudio         "LM Studio (Local)"
```

---

## Phase 1: Apple Foundation Models Provider

**Effort:** Small (1 session)
**Risk:** Medium (API shape needs verification at implementation time)
**Value:** Very high — instant zero-config local AI for all macOS 26+ users

### Background

Since we target macOS 26.2, Apple's `FoundationModels` framework is available at the system level. It provides:
- Pre-installed on-device language model optimized for Apple Silicon
- `LanguageModelSession` API with streaming text generation
- System-managed memory — OS handles loading/unloading
- No downloads, no configuration, no model management needed

### Limitations
- No image/vision support in the initial macOS 26 release
- Model quality is unknown vs. open-weight models (likely good for structured tasks)
- Not available on Intel Macs
- Slide images will be silently ignored — warn user in UI

### Step 1.1: Create FoundationModelProvider

**New file:** `Teleprompter/LLM/FoundationModelProvider.swift`

> **IMPORTANT:** The exact Foundation Models API shape below is approximate and MUST be verified against Apple's documentation at implementation time. The framework was released with macOS 26 and the streaming API, system instructions format, and multi-turn conversation support may differ from what's shown here.

```swift
import Foundation
import FoundationModels

final class FoundationModelProvider: LLMProvider, @unchecked Sendable {

    var displayName: String { "Apple On-Device (Built-in)" }

    var supportsParallelGeneration: Bool { false }

    var isAvailable: Bool {
        get async {
            // VERIFY: The actual availability API. Likely:
            // SystemLanguageModel.default.availability == .available
            // Returns false on Intel Macs or if model not yet downloaded.
            // DO NOT hardcode `return true`.
            let availability = SystemLanguageModel.default.availability
            switch availability {
            case .available:
                return true
            default:
                return false
            }
        }
    }

    // Retain the session for multi-turn conversation support.
    // Creating a new session per call throws away framework-side context.
    private var session: LanguageModelSession?

    func stream(messages: [ChatMessage]) async throws -> AsyncStream<String> {
        // VERIFY: Actual API shape. Key things to check:
        // 1. Does LanguageModelSession accept Instructions for system prompt?
        // 2. Does streamResponse return structured objects or strings?
        // 3. How does multi-turn work — replay messages or session-managed?

        // Extract system prompt for Instructions
        let systemContent = messages.first { $0.role == .system }?.content ?? ""

        // Create session with system instructions (retain for multi-turn)
        if session == nil {
            session = LanguageModelSession(instructions: systemContent)
        }

        // Build the user message (last user message in the conversation)
        let userMessage = messages.last { $0.role == .user }?.content ?? ""

        let currentSession = session!

        return AsyncStream { continuation in
            Task {
                do {
                    // VERIFY: streamResponse likely returns AsyncSequence of
                    // LanguageModelResponse objects, not raw strings.
                    // Extract text via response.content or similar property.
                    let stream = currentSession.streamResponse(to: userMessage)
                    for try await partial in stream {
                        // VERIFY: How to extract text from the response object.
                        // Might be: partial.content, partial.text, or String(describing: partial)
                        let text = String(describing: partial)
                        continuation.yield(text)
                    }
                } catch {
                    continuation.yield("\n\n[Error: \(error.localizedDescription)]")
                }
                continuation.finish()
            }
        }
    }

    /// Reset the session (call when clearing chat history).
    func resetSession() {
        session = nil
    }
}
```

### Step 1.2: Add `supportsParallelGeneration` to LLMProvider protocol

**File to modify:** `Teleprompter/LLM/LLMProvider.swift`

```swift
protocol LLMProvider: Sendable {
    func stream(messages: [ChatMessage]) async throws -> AsyncStream<String>
    var displayName: String { get }
    var isAvailable: Bool { get async }
    var supportsParallelGeneration: Bool { get }
}

// Default implementation for existing providers (Claude CLI, LM Studio)
extension LLMProvider {
    var supportsParallelGeneration: Bool { true }
}
```

Override to `false` in `FoundationModelProvider` and `MLXProvider`.

### Step 1.3: Wire into ProviderChoice

**File to modify:** `Teleprompter/Views/ScriptAssistant/ScriptAssistantView.swift`

```swift
enum ProviderChoice: String, CaseIterable {
    case foundationModel = "Apple On-Device"
    case mlxLocal = "Local Model (MLX)"
    case claudeCLI = "Claude Code CLI"
    case lmStudio = "LM Studio (Local)"
}
```

In `makeProvider()`:

```swift
case .foundationModel:
    let fm = FoundationModelProvider()
    guard await fm.isAvailable else {
        providerError = "On-device AI requires Apple Silicon with macOS 26. The model may still be downloading."
        showingProviderError = true
        return nil
    }
    return fm
```

### Step 1.4: Use `supportsParallelGeneration` in ConversationManager

**File to modify:** `Teleprompter/Services/ConversationManager.swift`

In `generateAllSlides()`, respect the provider's capability:

```swift
@MainActor
func generateAllSlides(maxConcurrency: Int = 3) async {
    // Local models must generate sequentially — GPU is shared
    let effectiveConcurrency = provider.supportsParallelGeneration ? maxConcurrency : 1
    // Use effectiveConcurrency in the AsyncSemaphore:
    let semaphore = AsyncSemaphore(limit: effectiveConcurrency)
    // ... rest unchanged
}
```

### Step 1.5: Keep default provider dynamic (DON'T hardcode foundationModel)

**File to modify:** `Teleprompter/Services/AppSettings.swift`

Do NOT change the default to `"foundationModel"` unconditionally — Intel Macs can't use it. Instead, detect at runtime:

```swift
var defaultProvider: String {
    get {
        if let saved = defaults.string(forKey: "defaultProvider") { return saved }
        // Auto-detect best default based on hardware
        #if arch(arm64)
        return "Apple On-Device"  // Apple Silicon — Foundation Models available
        #else
        return "LM Studio (Local)"  // Intel — fall back to LM Studio
        #endif
    }
    set { defaults.set(newValue, forKey: "defaultProvider") }
}
```

### Phase 1 files summary

| Action | File |
|--------|------|
| **Create** | `Teleprompter/LLM/FoundationModelProvider.swift` |
| **Modify** | `Teleprompter/LLM/LLMProvider.swift` — add `supportsParallelGeneration` |
| **Modify** | `Teleprompter/Views/ScriptAssistant/ScriptAssistantView.swift` — expand `ProviderChoice`, `makeProvider()` |
| **Modify** | `Teleprompter/Services/ConversationManager.swift` — use `supportsParallelGeneration` |
| **Modify** | `Teleprompter/Services/AppSettings.swift` — runtime default provider detection |
| **Modify** | `TeleprompterTests/Helpers/MockLLMProvider.swift` — add `supportsParallelGeneration` |

---

## Phase 2: MLX Swift Provider Core

**Effort:** Large (2-3 sessions)
**Risk:** Medium (SPM build complexity, API surface may change)

### Background: MLX Swift

[mlx-swift](https://github.com/ml-explore/mlx-swift) is Apple's machine learning framework for Apple Silicon. The companion repo [mlx-swift-examples](https://github.com/ml-explore/mlx-swift-examples) contains a high-level `LLM` library that handles:
- Model loading from Hugging Face Hub (automatic download + caching)
- Tokenization via `swift-transformers` (reads `tokenizer_config.json` from HF repos)
- Chat template application (ChatML, Llama, Mistral — all handled automatically via Jinja templates)
- Token generation with streaming callbacks
- Vision Language Model (VLM) support (Qwen2-VL, Paligemma, etc.)

### Step 2.1: Add SPM dependencies

**File to modify:** `Teleprompter.xcodeproj` (via Xcode UI)

Add package dependency:
- **URL:** `https://github.com/ml-explore/mlx-swift-examples`
- **Version:** Pin to a specific **release tag** (NOT `main` branch — a breaking upstream change will kill builds). Check the latest stable tag at implementation time.
- **Target to add:** the `LLM` library target from `Libraries/LLM`

This pulls in transitively:
```
mlx-swift-examples/Libraries/LLM
  ├── mlx-swift (MLX, MLXFast, MLXNN, MLXOptimizers, MLXLinalg, MLXRandom)
  ├── mlx-swift-examples/Libraries/Tokenizers
  │   └── swift-transformers (huggingface/swift-transformers)
  │       └── jinja (template engine for chat templates)
  └── swift-argument-parser (transitive, unused by us)
```

**Build time warning:** First build after adding MLX will take 5-10 minutes — it compiles C++/Metal shader kernels. Subsequent builds are cached.

### Step 2.2: Create MLXModelInfo

**New file:** `Teleprompter/LLM/MLXModelInfo.swift`

```swift
import Foundation

struct MLXModelInfo: Identifiable, Codable, Hashable {
    var id: String { repoId }

    /// Hugging Face repo ID (e.g., "mlx-community/Qwen2.5-3B-Instruct-4bit")
    let repoId: String

    /// Human-readable name
    let name: String

    /// Parameter count description (e.g., "3B", "7B")
    let parameterCount: String

    /// Quantization level (e.g., "4-bit", "8-bit", "fp16")
    let quantization: String

    /// Approximate size on disk in bytes
    let sizeOnDisk: UInt64

    /// Whether this model supports vision/image inputs
    let supportsVision: Bool

    /// Minimum RAM recommended to run this model (in bytes)
    let minimumRAM: UInt64

    /// Where the model comes from
    let source: ModelSource

    enum ModelSource: String, Codable {
        case huggingFace     // Downloaded from HF Hub
        case local           // User-provided local path
        case recommended     // From our curated list
    }
}

// MARK: - Recommended Models (all verified on HF as of 2026-03-13)

extension MLXModelInfo {

    static let recommended: [MLXModelInfo] = [
        // --- 8 GB Macs ---
        MLXModelInfo(
            repoId: "mlx-community/Qwen2.5-3B-Instruct-4bit",
            name: "Qwen 2.5 3B Instruct",
            parameterCount: "3B",
            quantization: "4-bit",
            sizeOnDisk: 1_740_000_000,      // 1.74 GB
            supportsVision: false,
            minimumRAM: 8_000_000_000,
            source: .recommended
        ),
        MLXModelInfo(
            repoId: "mlx-community/Phi-4-mini-instruct-4bit",
            name: "Phi-4 Mini Instruct",
            parameterCount: "3.8B",
            quantization: "4-bit",
            sizeOnDisk: 2_160_000_000,      // 2.16 GB
            supportsVision: false,
            minimumRAM: 8_000_000_000,
            source: .recommended
        ),

        // --- 16 GB Macs ---
        MLXModelInfo(
            repoId: "mlx-community/Qwen2.5-7B-Instruct-4bit",
            name: "Qwen 2.5 7B Instruct",
            parameterCount: "7B",
            quantization: "4-bit",
            sizeOnDisk: 4_280_000_000,      // 4.28 GB
            supportsVision: false,
            minimumRAM: 16_000_000_000,
            source: .recommended
        ),
        MLXModelInfo(
            repoId: "mlx-community/Mistral-7B-Instruct-v0.3-4bit",
            name: "Mistral 7B Instruct v0.3",
            parameterCount: "7B",
            quantization: "4-bit",
            sizeOnDisk: 4_080_000_000,      // 4.08 GB
            supportsVision: false,
            minimumRAM: 16_000_000_000,
            source: .recommended
        ),
        MLXModelInfo(
            repoId: "mlx-community/Meta-Llama-3.1-8B-Instruct-4bit",
            name: "Llama 3.1 8B Instruct",
            parameterCount: "8B",
            quantization: "4-bit",
            sizeOnDisk: 4_520_000_000,      // 4.52 GB
            supportsVision: false,
            minimumRAM: 16_000_000_000,
            source: .recommended
        ),

        // --- 32 GB+ Macs ---
        MLXModelInfo(
            repoId: "mlx-community/Mistral-Small-24B-Instruct-2501-4bit",
            name: "Mistral Small 24B",
            parameterCount: "24B",
            quantization: "4-bit",
            sizeOnDisk: 13_300_000_000,     // 13.3 GB
            supportsVision: false,
            minimumRAM: 32_000_000_000,
            source: .recommended
        ),
        MLXModelInfo(
            repoId: "mlx-community/Devstral-Small-2-24B-Instruct-2512-4bit",
            name: "Devstral Small 2 24B (code/instruct)",
            parameterCount: "24B",
            quantization: "4-bit",
            sizeOnDisk: 14_100_000_000,     // 14.1 GB
            supportsVision: false,
            minimumRAM: 32_000_000_000,
            source: .recommended
        ),
    ]

    /// Returns the best recommended model for the current machine's RAM.
    static var bestForThisMachine: MLXModelInfo {
        let ram = ProcessInfo.processInfo.physicalMemory
        let suitable = recommended.filter { $0.minimumRAM <= ram }
        return suitable.last ?? recommended.first!
    }
}
```

### Step 2.3: Create MLXModelManager

**New file:** `Teleprompter/LLM/MLXModelManager.swift`

This is the core model lifecycle manager — handles discovery, download, loading, and unloading.

**Key design decisions from review:**
- Heavy work (directory scanning, size calculation) runs on a background thread, NOT `@MainActor`
- Only state properties are `@MainActor` for UI updates
- Includes download cancellation and model deletion
- Uses `DispatchSource.makeMemoryPressureSource()` for macOS memory pressure (NOT `ProcessInfo.didReceiveMemoryWarningNotification` which is iOS-only)

```swift
import Foundation
import LLM          // from mlx-swift-examples
import MLX          // for GPU.clearCache()
import MLXLMCommon  // for ModelConfiguration, ModelContainer

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

    init() {
        setupMemoryPressureObserver()
    }

    // MARK: - Memory Pressure (macOS — NOT iOS notification)

    private func setupMemoryPressureObserver() {
        let source = DispatchSource.makeMemoryPressureSource(
            eventMask: [.warning, .critical],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            Task { @MainActor in
                self?.unloadModel()
            }
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

                // Merge with recommended list
                var merged = MLXModelInfo.recommended
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
        var discovered: [MLXModelInfo] = []

        // Hugging Face cache: ~/.cache/huggingface/hub/models--*
        let hfCache = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cache/huggingface/hub")
        discovered += scanHuggingFaceCache(at: hfCache)

        return discovered
    }

    /// Check if a model's files are already downloaded locally.
    func isDownloaded(_ model: MLXModelInfo) -> Bool {
        let hfCache = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cache/huggingface/hub")
        let modelDir = hfCache.appendingPathComponent(
            "models--\(model.repoId.replacingOccurrences(of: "/", with: "--"))"
        )
        return FileManager.default.fileExists(atPath: modelDir.path)
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

                // VERIFY: The exact progress callback API of LLMModelFactory.
                // The plan shows a Progress-like object — check the actual mlx-swift-examples
                // source for the current signature before implementing.
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
                _ = container  // just needed to trigger download

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

        let config = ModelConfiguration(id: model.repoId)
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
        GPU.clearCache()
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

        // Delete from HF cache
        let hfCache = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cache/huggingface/hub")
        let modelDir = hfCache.appendingPathComponent(
            "models--\(model.repoId.replacingOccurrences(of: "/", with: "--"))"
        )
        try? FileManager.default.removeItem(at: modelDir)

        scanForModels()
    }

    // MARK: - Memory

    var systemRAM: UInt64 { ProcessInfo.processInfo.physicalMemory }

    var systemRAMDescription: String {
        String(format: "%.0f GB", Double(systemRAM) / 1_073_741_824)
    }

    func canFitInRAM(_ model: MLXModelInfo) -> Bool {
        model.minimumRAM <= systemRAM
    }

    // MARK: - Private Helpers

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

            // Sort by modification date to get the latest snapshot
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

    private func directorySize(at url: URL) -> UInt64 {
        let enumerator = FileManager.default.enumerator(
            at: url, includingPropertiesForKeys: [.fileSizeKey]
        )
        var total: UInt64 = 0
        while let file = enumerator?.nextObject() as? URL {
            let size = (try? file.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
            total += UInt64(size)
        }
        return total
    }
}
```

### Step 2.4: Create MLXProvider

**New file:** `Teleprompter/LLM/MLXProvider.swift`

> **IMPORTANT:** The exact API for `MLXLMCommon.generate()`, `context.processor.prepare()`, and the token callback shape MUST be verified against the current version of `mlx-swift-examples` at implementation time. The library is actively developed and these signatures may differ from what's shown below. Check `Libraries/LLM/LLMModelFactory.swift` and `Libraries/MLXLMCommon/` in the repo.

```swift
import Foundation
import LLM
import MLXLMCommon

final class MLXProvider: LLMProvider, @unchecked Sendable {

    let modelInfo: MLXModelInfo

    init(modelInfo: MLXModelInfo) {
        self.modelInfo = modelInfo
    }

    var displayName: String {
        "MLX: \(modelInfo.name)"
    }

    var supportsParallelGeneration: Bool { false }

    var isAvailable: Bool {
        get async {
            await MLXModelManager.shared.loadState == .loaded
        }
    }

    func stream(messages: [ChatMessage]) async throws -> AsyncStream<String> {
        guard let container = await MLXModelManager.shared.modelContainer else {
            return AsyncStream { continuation in
                continuation.yield("[Error: No model loaded. Open Settings > Models to download one.]")
                continuation.finish()
            }
        }

        // Convert our ChatMessage format to the format mlx-swift-examples expects
        // Skip images for non-vision models
        let mlxMessages: [[String: String]] = messages.compactMap { msg in
            switch msg.role {
            case .system:
                return ["role": "system", "content": msg.content]
            case .user:
                return ["role": "user", "content": msg.content]
            case .assistant:
                return ["role": "assistant", "content": msg.content]
            }
        }

        let temperature = AppSettings.shared.mlxTemperature
        let topP = AppSettings.shared.mlxTopP
        let maxTokens = AppSettings.shared.mlxMaxTokens

        return AsyncStream { continuation in
            // Set up cancellation handler to stop Metal compute
            let generateTask = Task {
                do {
                    // VERIFY: Exact API shape of container.perform and generate
                    let result = try await container.perform { context in
                        let input = try await context.processor.prepare(
                            input: .init(messages: mlxMessages)
                        )

                        let params = GenerateParameters(
                            temperature: Float(temperature),
                            topP: Float(topP),
                            repetitionPenalty: 1.1
                        )

                        // VERIFY: Token callback shape — does it receive
                        // accumulated tokens or just the latest?
                        return try MLXLMCommon.generate(
                            input: input,
                            parameters: params,
                            context: context
                        ) { tokens in
                            if Task.isCancelled { return .stop }

                            let text = context.tokenizer.decode(tokens: [tokens.last!])
                            continuation.yield(text)

                            return tokens.count < maxTokens ? .more : .stop
                        }
                    }
                    _ = result
                } catch {
                    if !Task.isCancelled {
                        continuation.yield("\n\n[Error: \(error.localizedDescription)]")
                    }
                }
                continuation.finish()
            }

            // Cancel Metal compute when stream is terminated
            continuation.onTermination = { _ in
                generateTask.cancel()
            }
        }
    }
}
```

### Step 2.5: Add MLX settings to AppSettings

**File to modify:** `Teleprompter/Services/AppSettings.swift`

```swift
// MARK: - MLX Local Model

var mlxSelectedModelId: String {
    get { defaults.string(forKey: "mlxSelectedModelId") ?? "" }
    set { defaults.set(newValue, forKey: "mlxSelectedModelId") }
}

var mlxTemperature: Double {
    get { defaults.object(forKey: "mlxTemperature") as? Double ?? 0.7 }
    set { defaults.set(newValue, forKey: "mlxTemperature") }
}

var mlxTopP: Double {
    get { defaults.object(forKey: "mlxTopP") as? Double ?? 0.9 }
    set { defaults.set(newValue, forKey: "mlxTopP") }
}

var mlxMaxTokens: Int {
    get { defaults.object(forKey: "mlxMaxTokens") as? Int ?? 2048 }
    set { defaults.set(newValue, forKey: "mlxMaxTokens") }
}
```

### Step 2.6: Wire MLX into ScriptAssistantView

**File to modify:** `Teleprompter/Views/ScriptAssistant/ScriptAssistantView.swift`

Add case in `makeProvider()`:

```swift
case .mlxLocal:
    let manager = MLXModelManager.shared
    guard let modelInfo = manager.selectedModel else {
        providerError = "No local model selected. Open Settings > Models to download one."
        showingProviderError = true
        return nil
    }
    if await manager.loadState != .loaded {
        do {
            try await manager.loadModel(modelInfo)
        } catch {
            providerError = "Failed to load model: \(error.localizedDescription)"
            showingProviderError = true
            return nil
        }
    }
    return MLXProvider(modelInfo: modelInfo)
```

### Step 2.7: Validate custom HF repo IDs

When a user enters a custom repo ID in the model manager, validate it's an MLX-format model before attempting download:

```swift
/// Quick check that a HF repo looks like an MLX model.
/// Downloads just the config.json to check architecture compatibility.
static func validateMLXRepo(repoId: String) async -> Bool {
    let configURL = URL(string: "https://huggingface.co/\(repoId)/resolve/main/config.json")!
    guard let (data, _) = try? await URLSession.shared.data(from: configURL),
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          json["model_type"] != nil else {
        return false
    }
    // Check for safetensors (MLX format)
    let weightURL = URL(string: "https://huggingface.co/api/models/\(repoId)")!
    guard let (apiData, _) = try? await URLSession.shared.data(from: weightURL),
          let apiJson = try? JSONSerialization.jsonObject(with: apiData) as? [String: Any],
          let siblings = apiJson["siblings"] as? [[String: Any]] else {
        return false
    }
    return siblings.contains { ($0["rfilename"] as? String)?.hasSuffix(".safetensors") ?? false }
}
```

### Phase 2 files summary

| Action | File |
|--------|------|
| **Create** | `Teleprompter/LLM/MLXModelInfo.swift` |
| **Create** | `Teleprompter/LLM/MLXModelManager.swift` |
| **Create** | `Teleprompter/LLM/MLXProvider.swift` |
| **Modify** | `Teleprompter.xcodeproj` — add mlx-swift-examples SPM package (pinned tag) |
| **Modify** | `Teleprompter/Services/AppSettings.swift` — add MLX settings |
| **Modify** | `Teleprompter/Views/ScriptAssistant/ScriptAssistantView.swift` — add `.mlxLocal` case |

---

## Phase 3: Model Manager UI

**Effort:** Medium (1-2 sessions)
**Risk:** Low

### Step 3.1: Create ModelManagerView

**New file:** `Teleprompter/Views/Settings/ModelManagerView.swift`

Layout:

```
┌─────────────────────────────────────────────────┐
│  Local Models                    System: 16 GB  │
│─────────────────────────────────────────────────│
│                                                 │
│  RECOMMENDED FOR YOUR MAC                       │
│  ┌───────────────────────────────────────────┐  │
│  │ ★ Qwen 2.5 7B Instruct    4.3 GB  4-bit │  │
│  │   Best quality for 16GB Macs              │  │
│  │   [Download]  or  [✓ Downloaded - Select] │  │
│  └───────────────────────────────────────────┘  │
│                                                 │
│  ALL MODELS                                     │
│  ┌───────────────────────────────────────────┐  │
│  │ Qwen 2.5 3B          1.7 GB  4-bit ✓ 8GB │  │
│  │ Phi-4 Mini            2.2 GB  4-bit ✓ 8GB │  │
│  │ Qwen 2.5 7B          4.3 GB  4-bit ✓16GB │  │
│  │ Mistral 7B v0.3      4.1 GB  4-bit ✓16GB │  │
│  │ Llama 3.1 8B         4.5 GB  4-bit ✓16GB │  │
│  │ Mistral Small 24B   13.3 GB  4-bit ⚠32GB │  │
│  │ Devstral Small 24B  14.1 GB  4-bit ⚠32GB │  │
│  └───────────────────────────────────────────┘  │
│                                                 │
│  CUSTOM MODEL                                   │
│  HF Repo ID: [mlx-community/...        ] [Get] │
│  ⚠ Only MLX-format models (from mlx-community)  │
│  ─── or ───                                     │
│  [Add Local Model Folder...]                    │
│                                                 │
│  GENERATION SETTINGS                            │
│  Temperature: [====●=====] 0.7                  │
│  Top-P:       [========●=] 0.9                  │
│  Max Tokens:  [2048 ▾]                          │
│                                                 │
│  DOWNLOAD PROGRESS (when active)                │
│  Downloading Qwen 2.5 7B... 2.1/4.3 GB  47%    │
│  [████████████░░░░░░░░░░░░] [Cancel]            │
│                                                 │
└─────────────────────────────────────────────────┘
```

Key features:
- Shows system RAM and which models fit
- Highlights the best recommended model for this machine
- Download with progress bar and **cancel** button
- **Delete** downloaded models (important for multi-GB files)
- Select/deselect active model
- Custom HF repo ID field with validation (must be MLX-format)
- "Add Local Model Folder" file picker
- Generation parameter sliders

### Step 3.2: Add Models tab to SettingsView

**File to modify:** `Teleprompter/Views/SettingsView.swift`

```swift
var body: some View {
    TabView {
        teleprompterTab
            .tabItem { Label("Teleprompter", systemImage: "play.rectangle") }

        aiTab
            .tabItem { Label("AI Assistant", systemImage: "sparkles") }

        ModelManagerView()
            .tabItem { Label("Models", systemImage: "cpu") }

        aboutTab
            .tabItem { Label("About", systemImage: "info.circle") }
    }
    .frame(width: 500, height: 550)  // increased from 450x400
}
```

### Step 3.3: Inline banner in ScriptAssistantView

When user selects MLX provider but no model is loaded:

```
┌────────────────────────────────────────────────┐
│  ⚠ No local model loaded                       │
│  [Download Recommended Model]  [Open Settings]  │
│                                                 │
│  Note: Slide images are not used with local     │
│  models (no vision support).                    │
└────────────────────────────────────────────────┘
```

### Phase 3 files summary

| Action | File |
|--------|------|
| **Create** | `Teleprompter/Views/Settings/ModelManagerView.swift` |
| **Modify** | `Teleprompter/Views/SettingsView.swift` — add Models tab, resize frame |
| **Modify** | `Teleprompter/Views/ScriptAssistant/ScriptAssistantView.swift` — inline "no model" banner |

---

## Phase 4: Polish & Testing

**Effort:** Small (1 session)
**Risk:** Low

### Step 4.1: Provider switching cleanup

**File to modify:** `Teleprompter/Views/ScriptAssistant/ScriptAssistantView.swift`

When switching away from MLX provider, unload the model to free memory:

```swift
private func switchProvider() {
    Task {
        // Unload MLX model when switching away to free GPU memory
        if selectedProvider != .mlxLocal {
            await MLXModelManager.shared.unloadModel()
        }
        // Reset Foundation Models session when switching away
        if selectedProvider != .foundationModel,
           let fm = conversation?.provider as? FoundationModelProvider {
            fm.resetSession()
        }
        guard let provider = await makeProvider() else { return }
        // ...
    }
}
```

### Step 4.2: Tests

**New file:** `TeleprompterTests/LLM/MLXModelManagerTests.swift`

Test:
- `MLXModelInfo.bestForThisMachine` returns appropriate model for current RAM
- `MLXModelInfo.recommended` list is non-empty and sorted by size
- `MLXModelManager.canFitInRAM()` correctly evaluates model vs system RAM
- `MLXModelManager.isDownloaded()` correctly checks HF cache directory structure
- All recommended model repo IDs are valid strings (no empty, no whitespace)

**Modify:** `TeleprompterTests/Helpers/MockLLMProvider.swift`

Add `var supportsParallelGeneration: Bool { true }` to satisfy updated protocol.

**Modify:** `TeleprompterTests/Services/ConversationManagerTests.swift`

Test that `generateAllSlides` uses `effectiveConcurrency = 1` when provider returns `supportsParallelGeneration = false`.

---

## Recommended Default Models by Machine

| RAM | Recommended | HF Repo ID | Disk | Quality |
|-----|------------|------------|------|---------|
| 8 GB | Qwen 2.5 3B | `mlx-community/Qwen2.5-3B-Instruct-4bit` | 1.7 GB | Good |
| 16 GB | Qwen 2.5 7B | `mlx-community/Qwen2.5-7B-Instruct-4bit` | 4.3 GB | Excellent |
| 32 GB+ | Devstral Small 24B | `mlx-community/Devstral-Small-2-24B-Instruct-2512-4bit` | 14.1 GB | Near-cloud |

**Why Qwen 2.5:** Best instruction-following in its size class. Handles structured output well (the `[SCRIPT_START]`/`[SCRIPT_END]` markers).

**Why Devstral for 32GB+:** Danny has confirmed real-world success with this model. 24B parameter count with 4-bit quantization fits comfortably in 32GB.

**Do NOT bundle a model in the app binary.** Even the smallest model is 1.7 GB. Prompt to download on first use.

---

## Risk Assessment

| Risk | Severity | Mitigation |
|------|----------|-----------|
| SPM build time | Medium | First build takes 5-10 min (C++/Metal). Warn developers. |
| Model too large for RAM | High | Show RAM indicator in UI. Refuse to load models exceeding system RAM. |
| Foundation Models API differs from plan | Medium | All Phase 1 code marked "VERIFY". Test against actual framework at implementation time. |
| MLX generate() API differs from plan | Medium | All Phase 2 code marked "VERIFY". Check mlx-swift-examples source at implementation time. |
| App Store sandboxing | High | HF cache at `~/.cache/huggingface/` inaccessible when sandboxed. Need custom cache directory or NSOpenPanel for user models. Document as future work. |
| Upstream SPM breaking changes | Medium | Pin to release tag, not `main` branch. |
| Non-MLX model entered in custom field | Low | Validate repo has `.safetensors` files before downloading. |
| Memory pressure | Medium | Use `DispatchSource.makeMemoryPressureSource()` to auto-unload on pressure. |
| Token generation speed | Low | 30-80 tok/s on Apple Silicon for 4-bit 7B. Acceptable for script gen. |

---

## Complete Files Summary (All Phases)

| Phase | Action | File |
|-------|--------|------|
| 1 | **Create** | `Teleprompter/LLM/FoundationModelProvider.swift` |
| 1 | **Modify** | `Teleprompter/LLM/LLMProvider.swift` |
| 1 | **Modify** | `Teleprompter/Services/AppSettings.swift` |
| 1 | **Modify** | `Teleprompter/Views/ScriptAssistant/ScriptAssistantView.swift` |
| 1 | **Modify** | `Teleprompter/Services/ConversationManager.swift` |
| 1 | **Modify** | `TeleprompterTests/Helpers/MockLLMProvider.swift` |
| 2 | **Create** | `Teleprompter/LLM/MLXModelInfo.swift` |
| 2 | **Create** | `Teleprompter/LLM/MLXModelManager.swift` |
| 2 | **Create** | `Teleprompter/LLM/MLXProvider.swift` |
| 2 | **Modify** | `Teleprompter.xcodeproj` (SPM dependency — pinned tag) |
| 2 | **Modify** | `Teleprompter/Services/AppSettings.swift` |
| 2 | **Modify** | `Teleprompter/Views/ScriptAssistant/ScriptAssistantView.swift` |
| 3 | **Create** | `Teleprompter/Views/Settings/ModelManagerView.swift` |
| 3 | **Modify** | `Teleprompter/Views/SettingsView.swift` |
| 3 | **Modify** | `Teleprompter/Views/ScriptAssistant/ScriptAssistantView.swift` |
| 4 | **Create** | `TeleprompterTests/LLM/MLXModelManagerTests.swift` |
| 4 | **Modify** | `TeleprompterTests/Helpers/MockLLMProvider.swift` |
| 4 | **Modify** | `TeleprompterTests/Services/ConversationManagerTests.swift` |

**Total: 7 new files, 9 files modified (some in multiple phases)**
