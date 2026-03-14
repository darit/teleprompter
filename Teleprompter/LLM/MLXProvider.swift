// Teleprompter/LLM/MLXProvider.swift
import Foundation
import MLXLLM
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

        // Convert our ChatMessage format to the format MLXLMCommon expects
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

        // Prepare the input
        let userInput = UserInput(messages: mlxMessages)
        let input = try await container.prepare(input: userInput)

        let params = GenerateParameters(
            maxTokens: maxTokens,
            temperature: Float(temperature),
            topP: Float(topP),
            repetitionPenalty: 1.1
        )

        // Use the AsyncStream-based generate API
        let generationStream = try await container.generate(input: input, parameters: params)

        return AsyncStream { continuation in
            let generateTask = Task {
                var tokenCount = 0
                do {
                    for await generation in generationStream {
                        if Task.isCancelled { break }
                        switch generation {
                        case .chunk(let text):
                            continuation.yield(text)
                            tokenCount += 1
                        case .info:
                            break
                        case .toolCall:
                            break
                        }
                    }
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
