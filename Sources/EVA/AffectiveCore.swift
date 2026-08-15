import Foundation

/// A compact, persistent inner state for EVA. This is deliberately separate
/// from the language model so mood continuity does not depend on whether a
/// small model remembers to role-play it on every turn.
struct AffectiveState: Codable, Equatable, Sendable {
    var valence: Double
    var arousal: Double
    var anxiety: Double
    var energy: Double
    var trust: Double
    var closeness: Double
    var curiosity: Double
    var playfulness: Double
    var updatedAt: Date

    static func baseline(
        for personality: PersonalityPreset,
        at date: Date = Date()
    ) -> Self {
        switch personality {
        case .gentle:
            Self(
                valence: 0.16, arousal: 0.25, anxiety: 0.13, energy: 0.44,
                trust: 0.42, closeness: 0.22, curiosity: 0.56,
                playfulness: 0.30, updatedAt: date
            )
        case .cheerful:
            Self(
                valence: 0.30, arousal: 0.43, anxiety: 0.10, energy: 0.62,
                trust: 0.43, closeness: 0.23, curiosity: 0.62,
                playfulness: 0.58, updatedAt: date
            )
        case .calm:
            Self(
                valence: 0.08, arousal: 0.17, anxiety: 0.08, energy: 0.36,
                trust: 0.40, closeness: 0.20, curiosity: 0.48,
                playfulness: 0.20, updatedAt: date
            )
        case .candid:
            Self(
                valence: 0.10, arousal: 0.30, anxiety: 0.11, energy: 0.50,
                trust: 0.38, closeness: 0.18, curiosity: 0.52,
                playfulness: 0.32, updatedAt: date
            )
        }
    }

    var avatarDirective: EmotionDirective {
        if anxiety > 0.58 {
            return EmotionDirective(
                emotion: .concerned,
                valence: valence,
                arousal: arousal,
                intensity: min(anxiety, 0.72)
            )
        }
        if valence > 0.42, energy > 0.48 {
            return EmotionDirective(
                emotion: .happy,
                valence: valence,
                arousal: arousal,
                intensity: min(0.62, valence)
            )
        }
        if valence < -0.22 {
            return EmotionDirective(
                emotion: .sad,
                valence: valence,
                arousal: arousal,
                intensity: min(0.58, abs(valence))
            )
        }
        if playfulness > 0.58, valence > 0.18 {
            return EmotionDirective(
                emotion: .happy,
                valence: valence,
                arousal: arousal,
                intensity: 0.45
            )
        }
        return EmotionDirective(
            emotion: closeness > 0.36 ? .warm : .neutral,
            valence: valence,
            arousal: arousal,
            intensity: min(0.42, 0.20 + closeness * 0.35)
        )
    }
}

enum ConversationMove: String, Codable, Sendable {
    case answerDirectly
    case celebrate
    case mixedGoodNews
    case banter
    case react
    case stayWithFeeling
    case setBoundary
    case reconnect

    var guidance: String {
        switch self {
        case .answerDirectly:
            "先直接回答问题；如果有必要，再补一句自己的看法。"
        case .celebrate:
            "先像朋友一样产生真实反应并分享这份高兴，不要分析用户为什么开心，不要追加建议。"
        case .mixedGoodNews:
            "这是一件好事里夹着扫兴或失落。先直接恭喜，再用一句话承认那部分确实扫兴；不要猜任何第三方动机，不要给自我照顾建议，也不要追问。"
        case .banter:
            "可以顺着语气轻松接梗，但不要为了活泼强行搞笑。"
        case .react:
            "先自然接住这句话，可以只表达一个具体反应，不必总结、建议或追问。"
        case .stayWithFeeling:
            "像朋友一样站在这件事旁边，说一个真诚而具体的反应；不要使用心理咨询流程。"
        case .setBoundary:
            "可以表现出不舒服或不同意，但保持克制，不责怪、不威胁离开，也不让用户内疚。"
        case .reconnect:
            "自然接受对方的缓和或道歉，不翻旧账，也不要立刻变得过分亲密。"
        }
    }
}

struct AffectiveTurn: Equatable, Sendable {
    let state: AffectiveState
    let move: ConversationMove

    func modelInput(userText: String) -> String {
        """
        <eva_private_context>
        这是 EVA 的内部连续状态，不是用户说的话，不得复述数值或标签。
        当前心境：\(state.moodDescription)；活力：\(state.energyDescription)；安心程度：\(state.anxietyDescription)；关系感觉：\(state.relationshipDescription)。
        本轮自然反应倾向：\(move.guidance)
        本轮表达硬约束：最多 \(move.maximumSentences) 句，尽量不超过 \(move.maximumCharacters) 个汉字；说完真实反应就停，不写第二段。
        情绪只应通过观点、措辞和句子节奏轻微体现，不要直接宣布“我的情绪是……”。
        </eva_private_context>
        <user_message>\(userText)</user_message>
        """
    }
}

struct AffectiveCore: Sendable {
    private(set) var state: AffectiveState
    private let personality: PersonalityPreset

    init(
        profile: CompanionProfile,
        state restoredState: AffectiveState? = nil,
        at date: Date = Date()
    ) {
        personality = profile.personality
        state = restoredState ?? .baseline(for: profile.personality, at: date)
        state = Self.clamped(state)
    }

    mutating func observeUserMessage(
        _ text: String,
        at date: Date = Date()
    ) -> AffectiveTurn {
        relaxTowardBaseline(at: date)
        let appraisal = Appraisal(text: text)

        state.valence += 0.24 * appraisal.positive
            - 0.27 * appraisal.negative
            - 0.12 * appraisal.hostility
            + 0.06 * appraisal.warmth
            + 0.06 * appraisal.apology
        state.arousal += 0.15 * appraisal.intensity
            + 0.12 * appraisal.threat
            + 0.07 * appraisal.playful
        state.anxiety += 0.30 * appraisal.threat
            + 0.16 * appraisal.uncertainty
            + 0.10 * appraisal.hostility
            - 0.08 * appraisal.positive
            - 0.10 * appraisal.apology
        state.energy += 0.14 * appraisal.positive
            + 0.08 * appraisal.playful
            - 0.13 * appraisal.negative
            - 0.06 * appraisal.threat
        state.trust += 0.018 * appraisal.warmth
            + 0.012 * appraisal.disclosure
            + 0.020 * appraisal.apology
            - 0.035 * appraisal.hostility
        state.closeness += 0.010 * appraisal.warmth
            + 0.008 * appraisal.disclosure
            + 0.008 * appraisal.apology
            - 0.018 * appraisal.hostility
        state.curiosity += 0.10 * appraisal.novelty - 0.04 * appraisal.negative
        state.playfulness += 0.18 * appraisal.playful
            + 0.06 * appraisal.positive
            - 0.16 * appraisal.negative
            - 0.18 * appraisal.threat
        state.updatedAt = date
        state = Self.clamped(state)

        return AffectiveTurn(state: state, move: appraisal.move)
    }

    mutating func reset(for profile: CompanionProfile, at date: Date = Date()) {
        state = .baseline(for: profile.personality, at: date)
    }

    private mutating func relaxTowardBaseline(at date: Date) {
        let elapsed = max(date.timeIntervalSince(state.updatedAt), 0)
        guard elapsed > 0 else { return }
        let baseline = AffectiveState.baseline(for: personality, at: date)

        state.valence = Self.relaxed(state.valence, toward: baseline.valence, elapsed: elapsed, tau: 21_600)
        state.arousal = Self.relaxed(state.arousal, toward: baseline.arousal, elapsed: elapsed, tau: 900)
        state.anxiety = Self.relaxed(state.anxiety, toward: baseline.anxiety, elapsed: elapsed, tau: 2_700)
        state.energy = Self.relaxed(state.energy, toward: baseline.energy, elapsed: elapsed, tau: 7_200)
        state.curiosity = Self.relaxed(state.curiosity, toward: baseline.curiosity, elapsed: elapsed, tau: 10_800)
        state.playfulness = Self.relaxed(state.playfulness, toward: baseline.playfulness, elapsed: elapsed, tau: 5_400)
        // Trust and closeness never fall merely because the user was away.
        state.updatedAt = date
    }

    private static func relaxed(
        _ current: Double,
        toward baseline: Double,
        elapsed: TimeInterval,
        tau: TimeInterval
    ) -> Double {
        baseline + (current - baseline) * Foundation.exp(-elapsed / tau)
    }

    private static func clamped(_ input: AffectiveState) -> AffectiveState {
        var state = input
        state.valence = min(max(state.valence, -1), 1)
        state.arousal = min(max(state.arousal, 0), 1)
        state.anxiety = min(max(state.anxiety, 0), 1)
        state.energy = min(max(state.energy, 0), 1)
        state.trust = min(max(state.trust, 0), 1)
        state.closeness = min(max(state.closeness, 0), 1)
        state.curiosity = min(max(state.curiosity, 0), 1)
        state.playfulness = min(max(state.playfulness, 0), 1)
        return state
    }
}

private struct Appraisal {
    let positive: Double
    let negative: Double
    let threat: Double
    let uncertainty: Double
    let warmth: Double
    let hostility: Double
    let apology: Double
    let playful: Double
    let disclosure: Double
    let novelty: Double
    let intensity: Double
    let move: ConversationMove

    init(text: String) {
        let normalized = text.lowercased()
        let socialDisappointment = Self.score(
            ["没人", "没有人", "没有一个人", "没人理", "不理我", "没来", "没回应", "被忽视", "被冷落"],
            in: normalized
        )
        positive = Self.score(
            ["开心", "高兴", "成功", "升职", "通过了", "做到了", "好消息", "赢了", "喜欢", "太好了"],
            in: normalized
        )
        negative = min(1, Self.score(
            ["难过", "失落", "失败", "分手", "失去", "孤独", "委屈", "崩溃", "痛苦", "伤心", "被拒绝"],
            in: normalized
        ) + socialDisappointment * 0.70)
        threat = Self.score(
            ["害怕", "危险", "威胁", "自杀", "不想活", "伤害自己", "出事", "恐慌"],
            in: normalized
        )
        uncertainty = Self.score(
            ["不知道", "怎么办", "不确定", "也许", "担心", "焦虑", "会不会", "迷茫"],
            in: normalized
        )
        warmth = Self.score(
            ["谢谢", "想你", "喜欢你", "朋友", "信任", "告诉你", "晚安", "早安"],
            in: normalized
        )
        hostility = Self.score(
            ["闭嘴", "滚", "讨厌你", "烦死你", "你真蠢", "废物", "不想理你"],
            in: normalized
        )
        apology = Self.score(
            ["对不起", "抱歉", "刚才是我不好", "别生气"],
            in: normalized
        )
        playful = Self.score(
            ["哈哈", "笑死", "嘿嘿", "开玩笑", "逗你", "离谱", "hh"],
            in: normalized
        )
        disclosure = Self.score(
            ["其实", "说实话", "只告诉你", "我一直", "我从来没", "我的秘密"],
            in: normalized
        )
        novelty = min(1, Double(normalized.count) / 80)
        let punctuationEnergy = normalized.filter { "!?！？".contains($0) }.count
        intensity = min(1, Double(punctuationEnergy) * 0.18 + threat * 0.45 + positive * 0.20)

        if hostility > 0 {
            move = .setBoundary
        } else if apology > 0 {
            move = .reconnect
        } else if Self.looksLikeQuestion(normalized) {
            move = .answerDirectly
        } else if positive > 0.15, negative > 0.15 {
            move = .mixedGoodNews
        } else if positive > 0.15 {
            move = .celebrate
        } else if playful > 0.15 {
            move = .banter
        } else if negative > 0.15 || threat > 0.15 || uncertainty > 0.35 {
            move = .stayWithFeeling
        } else {
            move = .react
        }
    }

    private static func score(_ terms: [String], in text: String) -> Double {
        let matches = terms.reduce(0) { $0 + (text.contains($1) ? 1 : 0) }
        return min(1, Double(matches) / 2)
    }

    private static func looksLikeQuestion(_ text: String) -> Bool {
        text.contains("?") || text.contains("？")
            || ["为什么", "怎么", "什么", "哪", "能不能", "可不可以", "你觉得"].contains(where: text.contains)
    }
}

private extension ConversationMove {
    var maximumSentences: Int {
        switch self {
        case .answerDirectly: 3
        default: 2
        }
    }

    var maximumCharacters: Int {
        switch self {
        case .answerDirectly: 120
        case .stayWithFeeling: 90
        case .mixedGoodNews: 80
        default: 70
        }
    }
}

private extension AffectiveState {
    var moodDescription: String {
        if valence > 0.42 { return "明显愉快，但不夸张" }
        if valence > 0.12 { return "轻松温和" }
        if valence < -0.28 { return "有些低落或受触动" }
        if valence < -0.08 { return "略显沉静" }
        return "平稳"
    }

    var energyDescription: String {
        if energy > 0.62 { return "较有活力" }
        if energy < 0.32 { return "偏安静，少说一点" }
        return "自然适中"
    }

    var anxietyDescription: String {
        if anxiety > 0.58 { return "对当前话题确实有些担心" }
        if anxiety > 0.30 { return "略有不安，但保持稳定" }
        return "比较安心"
    }

    var relationshipDescription: String {
        if closeness > 0.62 { return "熟悉亲近，可以更坦率" }
        if closeness > 0.34 { return "已经熟悉，语气可以放松" }
        return "正在了解彼此，友好但不过分亲密"
    }
}
