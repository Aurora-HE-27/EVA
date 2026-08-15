import Foundation
import HuggingFace
import MLXHuggingFace
import MLXLLM
import MLXLMCommon
import Tokenizers

@MainActor
final class LocalLanguageModel {
    enum LoadState: Equatable {
        case notLoaded
        case loading
        case ready
        case failed(String)
    }

    private(set) var loadState: LoadState = .notLoaded
    private var session: ChatSession?

    func prepare(
        systemPrompt: String,
        history: [ChatMessage] = []
    ) async throws {
        guard session == nil else { return }

        loadState = .loading
        do {
            let modelDirectory = try ModelStorage.languageModelURL()
            let container = try await LLMModelFactory.shared.loadContainer(
                from: modelDirectory,
                using: #huggingFaceTokenizerLoader()
            )
            let restoredHistory = history.compactMap(Self.modelMessage(from:))
            session = ChatSession(
                container,
                instructions: systemPrompt,
                history: restoredHistory,
                generateParameters: GenerateParameters(
                    maxTokens: 128,
                    maxKVSize: 4096,
                    kvBits: 8,
                    temperature: 0.68,
                    topP: 0.90,
                    repetitionPenalty: 1.05,
                    repetitionContextSize: 128
                ),
                additionalContext: ["enable_thinking": false]
            )
            loadState = .ready
        } catch {
            loadState = .failed(error.localizedDescription)
            throw error
        }
    }

    func streamResponse(
        to prompt: String,
        systemPrompt: String,
        history: [ChatMessage] = []
    ) async throws -> AsyncThrowingStream<String, Error> {
        try await prepare(systemPrompt: systemPrompt, history: history)
        guard let session else {
            throw AppError.localModelUnavailable
        }
        return session.streamResponse(to: prompt)
    }

    func resetConversation() async {
        await session?.clear()
    }

    private static func modelMessage(from message: ChatMessage) -> Chat.Message? {
        let content = message.content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { return nil }

        let role: Chat.Message.Role = switch message.role {
        case .system: .system
        case .user: .user
        case .assistant: .assistant
        }
        return Chat.Message(role: role, content: content)
    }
}
