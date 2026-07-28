import Foundation

struct OllamaClient: Sendable {
    struct APIMessage: Codable, Sendable {
        let role: String
        let content: String
    }

    private struct TagsResponse: Decodable {
        struct Model: Decodable {
            let name: String
        }

        let models: [Model]
    }

    private struct ChatRequest: Encodable {
        let model: String
        let messages: [APIMessage]
        let stream: Bool
        let options: Options

        struct Options: Encodable {
            let temperature: Double
            let num_ctx: Int
        }
    }

    private struct ChatChunk: Decodable {
        struct PartialMessage: Decodable {
            let content: String
        }

        let message: PartialMessage?
        let done: Bool?
        let error: String?
    }

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func models(serverURL: URL) async throws -> [OllamaModel] {
        let url = serverURL.appending(path: "api/tags")
        let (data, response) = try await session.data(from: url)
        try Self.validate(response: response, data: data)
        return try JSONDecoder()
            .decode(TagsResponse.self, from: data)
            .models
            .map { OllamaModel(name: $0.name) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    func streamChat(
        serverURL: URL,
        model: String,
        messages: [APIMessage]
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let url = serverURL.appending(path: "api/chat")
                    var request = URLRequest(url: url)
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.httpBody = try JSONEncoder().encode(
                        ChatRequest(
                            model: model,
                            messages: messages,
                            stream: true,
                            options: .init(temperature: 0.75, num_ctx: 8_192)
                        )
                    )

                    let (bytes, response) = try await session.bytes(for: request)
                    guard let httpResponse = response as? HTTPURLResponse,
                          200..<300 ~= httpResponse.statusCode else {
                        throw URLError(.badServerResponse)
                    }

                    for try await line in bytes.lines {
                        try Task.checkCancellation()
                        guard !line.isEmpty else { continue }
                        let chunk = try JSONDecoder().decode(
                            ChatChunk.self,
                            from: Data(line.utf8)
                        )
                        if let error = chunk.error {
                            throw OllamaServiceError(message: error)
                        }
                        if let token = chunk.message?.content, !token.isEmpty {
                            continuation.yield(token)
                        }
                        if chunk.done == true {
                            break
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

    private static func validate(response: URLResponse, data: Data) throws {
        guard let response = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        guard 200..<300 ~= response.statusCode else {
            let message = String(data: data, encoding: .utf8) ?? "HTTP \(response.statusCode)"
            throw OllamaServiceError(message: message)
        }
    }
}

struct OllamaServiceError: LocalizedError {
    let message: String

    var errorDescription: String? { message }
}
