// Teleprompter/LLM/LMStudioProvider.swift
import Foundation

final class LMStudioProvider: LLMProvider, @unchecked Sendable {

    let baseURL: URL
    private let modelName: String?
    private let session: URLSession

    init(baseURL: URL = URL(string: "http://localhost:1234")!,
         modelName: String? = nil,
         timeoutSeconds: TimeInterval = 600) {
        self.baseURL = baseURL
        self.modelName = modelName
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = timeoutSeconds
        config.timeoutIntervalForResource = timeoutSeconds
        self.session = URLSession(configuration: config)
    }

    var displayName: String {
        if let modelName {
            return "LM Studio (\(modelName))"
        }
        return "LM Studio"
    }

    var isAvailable: Bool {
        let semaphore = DispatchSemaphore(value: 0)
        let url = baseURL.appendingPathComponent("/v1/models")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 3

        var reachable = false
        let task = session.dataTask(with: request) { _, response, _ in
            if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                reachable = true
            }
            semaphore.signal()
        }
        task.resume()
        semaphore.wait()
        return reachable
    }

    // MARK: - Streaming

    func stream(messages: [ChatMessage]) async throws -> AsyncStream<String> {
        let body = buildRequestBody(messages: messages)
        let url = baseURL.appendingPathComponent("/v1/chat/completions")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (asyncBytes, response) = try await session.bytes(for: request)

        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            return AsyncStream { continuation in
                continuation.yield("[Error: LM Studio returned status \(statusCode)]")
                continuation.finish()
            }
        }

        return AsyncStream { continuation in
            Task.detached {
                do {
                    for try await line in asyncBytes.lines {
                        if let token = Self.parseSSELine(line) {
                            continuation.yield(token)
                        } else if line == "data: [DONE]" {
                            break
                        }
                    }
                } catch {
                    continuation.yield("\n\n[Error: \(error.localizedDescription)]")
                }
                continuation.finish()
            }
        }
    }

    // MARK: - Internal (visible for testing)

    func buildRequestBody(messages: [ChatMessage]) -> [String: Any] {
        let messageDicts: [[String: String]] = messages.map { msg in
            ["role": msg.role.rawValue, "content": msg.content]
        }

        var body: [String: Any] = [
            "messages": messageDicts,
            "stream": true
        ]

        if let modelName {
            body["model"] = modelName
        }

        return body
    }

    /// Parse a single SSE line and extract the content delta, if present.
    /// Returns `nil` for non-data lines, empty deltas, or the `[DONE]` sentinel.
    static func parseSSELine(_ line: String) -> String? {
        guard line.hasPrefix("data: ") else { return nil }

        let jsonString = String(line.dropFirst(6))
        guard jsonString != "[DONE]" else { return nil }

        guard let data = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let delta = choices.first?["delta"] as? [String: Any],
              let content = delta["content"] as? String else {
            return nil
        }

        return content
    }
}
