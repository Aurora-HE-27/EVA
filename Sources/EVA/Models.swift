import Foundation

enum CompanionGender: String, CaseIterable, Codable, Identifiable, Sendable {
    case feminine
    case masculine
    case neutral

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .feminine: "女生"
        case .masculine: "男生"
        case .neutral: "中性"
        }
    }

    var promptDescription: String {
        switch self {
        case .feminine: "自然年轻的女性表达"
        case .masculine: "自然年轻的男性表达"
        case .neutral: "不强调性别的自然表达"
        }
    }

    var defaultPitch: Double {
        switch self {
        case .feminine: 1.04
        case .masculine: 0.86
        case .neutral: 0.96
        }
    }
}

enum PersonalityPreset: String, CaseIterable, Codable, Identifiable, Sendable {
    case gentle
    case cheerful
    case calm
    case candid

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .gentle: "温柔治愈"
        case .cheerful: "开朗活泼"
        case .calm: "安静沉稳"
        case .candid: "真诚直接"
        }
    }

    var subtitle: String {
        switch self {
        case .gentle: "先共情，再轻轻陪你梳理"
        case .cheerful: "有生命力，但不会强行积极"
        case .calm: "克制、耐心，给情绪留出空间"
        case .candid: "不敷衍，温和地说真实想法"
        }
    }

    var promptDescription: String {
        switch self {
        case .gentle:
            "温柔细腻，善于确认感受，语气柔和但不黏腻"
        case .cheerful:
            "年轻开朗，有适度幽默感，会带来能量但不否定负面情绪"
        case .calm:
            "安静沉稳，措辞克制，善于留白，不急着提出解决方案"
        case .candid:
            "真诚直接，有自己的判断，不迎合，但始终尊重用户"
        }
    }

    var defaultRate: Double {
        switch self {
        case .gentle: 0.45
        case .cheerful: 0.51
        case .calm: 0.43
        case .candid: 0.48
        }
    }
}

struct CompanionProfile: Codable, Equatable, Sendable {
    var name: String
    var gender: CompanionGender
    var personality: PersonalityPreset
    var userName: String

    static let defaultProfile = CompanionProfile(
        name: "EVA",
        gender: .feminine,
        personality: .gentle,
        userName: ""
    )

    var sanitizedName: String {
        Self.sanitize(name, fallback: "EVA")
    }

    var sanitizedUserName: String {
        Self.sanitize(userName, fallback: "")
    }

    private static func sanitize(_ value: String, fallback: String) -> String {
        let singleLine = value
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let clipped = String(singleLine.prefix(20))
        return clipped.isEmpty ? fallback : clipped
    }
}

struct AppSettingsSnapshot: Equatable, Sendable {
    let selectedVoiceIdentifier: String
    let voiceRate: Double
    let voicePitch: Double
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

enum AppError: LocalizedError {
    case emptyResponse
    case localModelUnavailable
    case localModelMissing(URL)

    var errorDescription: String? {
        switch self {
        case .emptyResponse:
            "模型没有返回内容。"
        case .localModelUnavailable:
            "EVA 的本地语言模型尚未就绪。"
        case .localModelMissing(let url):
            "未找到 EVA 本地语言模型。开发模型目录：\(url.path)"
        }
    }
}
