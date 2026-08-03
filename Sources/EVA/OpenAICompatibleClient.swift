import Foundation

enum APIEndpointResolver {
    static func resolve(_ address: String) throws -> URL {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: trimmed),
              components.scheme == "https",
              let host = components.host,
              !host.isEmpty else {
            throw AppError.invalidAPIURL
        }

        let path = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if path.isEmpty {
            components.path = host.lowercased() == "api.openai.com"
                ? "/v1/chat/completions"
                : "/chat/completions"
        } else if path.split(separator: "/").last?.lowercased() == "v1" {
            components.path = "/\(path)/chat/completions"
        }

        guard let url = components.url else {
            throw AppError.invalidAPIURL
        }
        return url
    }
}

struct OpenAICompatibleClient: Sendable {
    private struct ChatRequest: Encodable {
        let model: String
        let messages: [ChatAPIMessage]
        let stream: Bool
        let temperature: Double
    }

    private struct ChatChunk: Decodable {
        struct Choice: Decodable {
            struct Delta: Decodable {
                let content: String?
            }

            let delta: Delta?
        }

        struct APIError: Decodable {
            let message: String?
        }

        let choices: [Choice]?
        let error: APIError?
    }

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func streamChat(
        endpointURL: URL,
        apiKey: String,
        model: String,
        messages: [ChatAPIMessage]
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var request = URLRequest(url: endpointURL)
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
                    request.timeoutInterval = 180
                    request.httpBody = try JSONEncoder().encode(
                        ChatRequest(
                            model: model,
                            messages: messages,
                            stream: true,
                            temperature: 0.75
                        )
                    )

                    let (bytes, response) = try await session.bytes(for: request)
                    guard let httpResponse = response as? HTTPURLResponse else {
                        throw URLError(.badServerResponse)
                    }
                    guard 200..<300 ~= httpResponse.statusCode else {
                        throw ChatServiceError(
                            message: "API 返回 HTTP \(httpResponse.statusCode)。请检查地址、模型和密钥。"
                        )
                    }

                    for try await rawLine in bytes.lines {
                        try Task.checkCancellation()
                        let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !line.isEmpty, line.hasPrefix("data:") else { continue }
                        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                        if payload == "[DONE]" { break }

                        let chunk = try JSONDecoder().decode(
                            ChatChunk.self,
                            from: Data(payload.utf8)
                        )
                        if let message = chunk.error?.message {
                            throw ChatServiceError(message: message)
                        }
                        for choice in chunk.choices ?? [] {
                            if let token = choice.delta?.content, !token.isEmpty {
                                continuation.yield(token)
                            }
                        }
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }
}
