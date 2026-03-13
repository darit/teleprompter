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
        request.timeoutInterval = 2

        var reachable = false
        // Use a dedicated session to avoid interfering with the main session on app close
        let checkConfig = URLSessionConfiguration.ephemeral
        checkConfig.timeoutIntervalForRequest = 2
        let checkSession = URLSession(configuration: checkConfig)
        let task = checkSession.dataTask(with: request) { _, response, _ in
            if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                reachable = true
            }
            semaphore.signal()
        }
        task.resume()
        _ = semaphore.wait(timeout: .now() + 3)
        checkSession.invalidateAndCancel()
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
        let messageDicts: [[String: Any]] = messages.map { msg in
            if msg.images.isEmpty {
                return ["role": msg.role.rawValue, "content": msg.content]
            }
            // OpenAI vision format: content is an array of text and image_url objects
            var contentParts: [[String: Any]] = [
                ["type": "text", "text": msg.content]
            ]
            for imageData in msg.images {
                let base64 = imageData.base64EncodedString()
                let mimeType = imageData.starts(with: [0x89, 0x50, 0x4E, 0x47]) ? "image/png" : "image/jpeg"
                contentParts.append([
                    "type": "image_url",
                    "image_url": ["url": "data:\(mimeType);base64,\(base64)"]
                ])
            }
            return ["role": msg.role.rawValue, "content": contentParts]
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
