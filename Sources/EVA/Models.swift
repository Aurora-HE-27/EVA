import Foundation

enum ChatBackendKind: String, CaseIterable, Codable, Identifiable, Sendable {
    case ollama
    case compatibleAPI

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .ollama: "本地 Ollama"
        case .compatibleAPI: "大模型 API"
        }
    }
}

struct ChatAPIMessage: Codable, Sendable {
    let role: String
    let content: String
}

struct AppSettingsSnapshot: Equatable, Sendable {
    let chatBackend: ChatBackendKind
    let selectedModel: String
    let serverAddress: String
    let apiEndpointAddress: String
    let apiModelName: String
    let apiKey: String
    let selectedVoiceIdentifier: String
    let voiceRate: Double
    let voicePitch: Double
    let avatarImagePath: String
}

enum EVAEmotion: String, CaseIterable, Codable, Sendable {
    case neutral
    case warm
    case happy
    case concerned
    case sad
    case surprised
    case focused

    var displayName: String {
        switch self {
        case .neutral: "平静"
        case .warm: "温柔"
        case .happy: "开心"
        case .concerned: "关心"
        case .sad: "低落"
        case .surprised: "惊喜"
        case .focused: "认真"
        }
    }
}

struct EmotionDirective: Equatable, Sendable {
    let emotion: EVAEmotion
    let valence: Double
    let arousal: Double
    let intensity: Double

    static let neutral = EmotionDirective(
        emotion: .neutral,
        valence: 0,
        arousal: 0.2,
        intensity: 0.25
    )

    init(
        emotion: EVAEmotion,
        valence: Double,
        arousal: Double,
        intensity: Double
    ) {
        self.emotion = emotion
        self.valence = min(max(valence, -1), 1)
        self.arousal = min(max(arousal, 0), 1)
        self.intensity = min(max(intensity, 0), 1)
    }
}

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
    case incompleteAPIConfiguration
    case invalidAPIURL

    var errorDescription: String? {
        switch self {
        case .noModel:
            "EVA 没有找到可用的 Ollama 模型。请先启动 Ollama 并下载一个模型。"
        case .emptyResponse:
            "模型没有返回内容。"
        case .invalidServerURL:
            "Ollama 服务地址无效。"
        case .incompleteAPIConfiguration:
            "API 配置不完整。请填写完整端点、模型名称和 API 密钥。"
        case .invalidAPIURL:
            "大模型 API 端点无效。"
        }
    }
}
