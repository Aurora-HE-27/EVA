import Foundation

struct ChatMessage: Identifiable, Codable, Equatable, Sendable {
    enum Role: String, Codable, Sendable {
        case system
        case user
        case assistant
    }

    let id: UUID
    let role: Role
    var content: String
    let createdAt: Date

    init(
        id: UUID = UUID(),
        role: Role,
        content: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.createdAt = createdAt
    }
}

enum AvatarState: String, Sendable {
    case idle
    case listening
    case thinking
    case speaking
    case happy
    case concerned

    var statusText: String {
        switch self {
        case .idle: "陪着你"
        case .listening: "正在听"
        case .thinking: "正在想"
        case .speaking: "正在说"
        case .happy: "很开心"
        case .concerned: "有点担心你"
        }
    }
}

struct OllamaModel: Identifiable, Codable, Hashable, Sendable {
    let name: String

    var id: String { name }
}

enum AppError: LocalizedError {
    case noModel
    case emptyResponse
    case invalidServerURL

    var errorDescription: String? {
        switch self {
        case .noModel:
            "没有可用的 Ollama 模型。请先启动 Ollama 并下载一个模型。"
        case .emptyResponse:
            "模型没有返回内容。"
        case .invalidServerURL:
            "Ollama 服务地址无效。"
        }
    }
}
