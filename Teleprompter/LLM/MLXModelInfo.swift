// Teleprompter/LLM/MLXModelInfo.swift
import Foundation

struct MLXModelInfo: Identifiable, Codable, Hashable {
    var id: String { repoId }

    /// Hugging Face repo ID (e.g., "mlx-community/Qwen2.5-3B-Instruct-4bit")
    /// For local models, this is "org/model-name" derived from the directory structure.
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

    /// Absolute path on disk for locally-discovered models (LM Studio, manual).
    /// When set, the model is loaded from this directory instead of downloading from HF.
    let localPath: String?

    enum ModelSource: String, Codable {
        case huggingFace
        case lmStudio
        case local
        case recommended
    }

    init(repoId: String, name: String, parameterCount: String, quantization: String,
         sizeOnDisk: UInt64, supportsVision: Bool, minimumRAM: UInt64,
         source: ModelSource, localPath: String? = nil) {
        self.repoId = repoId
        self.name = name
        self.parameterCount = parameterCount
        self.quantization = quantization
        self.sizeOnDisk = sizeOnDisk
        self.supportsVision = supportsVision
        self.minimumRAM = minimumRAM
        self.source = source
        self.localPath = localPath
    }
}

// MARK: - Recommended Models

extension MLXModelInfo {

    static let recommended: [MLXModelInfo] = [
        // --- 8 GB Macs ---
        MLXModelInfo(
            repoId: "mlx-community/Qwen2.5-3B-Instruct-4bit",
            name: "Qwen 2.5 3B Instruct",
            parameterCount: "3B",
            quantization: "4-bit",
            sizeOnDisk: 1_740_000_000,
            supportsVision: false,
            minimumRAM: 8_000_000_000,
            source: .recommended
        ),
        MLXModelInfo(
            repoId: "mlx-community/Phi-4-mini-instruct-4bit",
            name: "Phi-4 Mini Instruct",
            parameterCount: "3.8B",
            quantization: "4-bit",
            sizeOnDisk: 2_160_000_000,
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
            sizeOnDisk: 4_280_000_000,
            supportsVision: false,
            minimumRAM: 16_000_000_000,
            source: .recommended
        ),
        MLXModelInfo(
            repoId: "mlx-community/Mistral-7B-Instruct-v0.3-4bit",
            name: "Mistral 7B Instruct v0.3",
            parameterCount: "7B",
            quantization: "4-bit",
            sizeOnDisk: 4_080_000_000,
            supportsVision: false,
            minimumRAM: 16_000_000_000,
            source: .recommended
        ),
        MLXModelInfo(
            repoId: "mlx-community/Meta-Llama-3.1-8B-Instruct-4bit",
            name: "Llama 3.1 8B Instruct",
            parameterCount: "8B",
            quantization: "4-bit",
            sizeOnDisk: 4_520_000_000,
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
            sizeOnDisk: 13_300_000_000,
            supportsVision: false,
            minimumRAM: 32_000_000_000,
            source: .recommended
        ),
        MLXModelInfo(
            repoId: "mlx-community/Devstral-Small-2-24B-Instruct-2512-4bit",
            name: "Devstral Small 2 24B (code/instruct)",
            parameterCount: "24B",
            quantization: "4-bit",
            sizeOnDisk: 14_100_000_000,
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
