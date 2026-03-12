// Teleprompter/LLM/ClaudeCLIProvider.swift
import Foundation

final class ClaudeCLIProvider: LLMProvider, @unchecked Sendable {

    enum Model: String, Sendable {
        case opus
        case sonnet
    }

    let model: Model
    private let timeoutSeconds: TimeInterval

    init(model: Model = .sonnet, timeoutSeconds: TimeInterval = 300) {
        self.model = model
        self.timeoutSeconds = timeoutSeconds
    }

    var displayName: String {
        "Claude Code CLI (\(model.rawValue.capitalized))"
    }

    var isAvailable: Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = ["claude"]
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    func stream(messages: [ChatMessage]) async throws -> AsyncStream<String> {
        let prompt = Self.formatPrompt(messages: messages)

        return AsyncStream { continuation in
            Task.detached {
                do {
                    let process = Process()
                    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
                    process.arguments = ["claude"] + self.buildArguments()

                    let inputPipe = Pipe()
                    let outputPipe = Pipe()
                    let errorPipe = Pipe()

                    process.standardInput = inputPipe
                    process.standardOutput = outputPipe
                    process.standardError = errorPipe

                    try process.run()

                    // Write prompt to stdin and close
                    let promptData = prompt.data(using: .utf8) ?? Data()
                    inputPipe.fileHandleForWriting.write(promptData)
                    inputPipe.fileHandleForWriting.closeFile()

                    // Read stdout in fixed-size chunks (4096 bytes)
                    let handle = outputPipe.fileHandleForReading
                    var data = handle.readData(ofLength: 4096)
                    while !data.isEmpty {
                        if let chunk = String(data: data, encoding: .utf8) {
                            continuation.yield(chunk)
                        }
                        data = handle.readData(ofLength: 4096)
                    }

                    process.waitUntilExit()

                    if process.terminationStatus != 0 {
                        let errData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                        let errMsg = String(data: errData, encoding: .utf8) ?? "Unknown error"
                        continuation.yield("\n\n[Error: Claude CLI exited with code \(process.terminationStatus): \(errMsg)]")
                    }

                    continuation.finish()
                } catch {
                    continuation.yield("\n\n[Error: \(error.localizedDescription)]")
                    continuation.finish()
                }
            }
        }
    }

    // MARK: - Internal (visible for testing)

    func buildArguments() -> [String] {
        ["-p", "--model", model.rawValue]
    }

    static func formatPrompt(messages: [ChatMessage]) -> String {
        var parts: [String] = []

        for message in messages {
            switch message.role {
            case .system:
                parts.append("[System Instructions]\n\(message.content)")
            case .user:
                parts.append("[User]\n\(message.content)")
            case .assistant:
                parts.append("[Assistant]\n\(message.content)")
            }
        }

        return parts.joined(separator: "\n\n---\n\n")
    }
}
