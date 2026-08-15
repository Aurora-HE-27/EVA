import Combine
import Foundation

@MainActor
final class AppState: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var draft = ""
    @Published var profile = CompanionProfile.defaultProfile
    @Published var hasCompletedOnboarding = false
    @Published var selectedVoiceIdentifier = ""
    @Published var voiceRate = 0.47
    @Published var voicePitch = 1.02
    @Published var avatarState: AvatarState = .idle
    @Published var avatarEmotion: EmotionDirective = .neutral
    @Published var isGenerating = false
    @Published var isLocalModelReady = false
    @Published var connectionStatus = "正在准备本地模型…"
    @Published var errorMessage: String?
    @Published var showsSettings = false

    let speechInput = SpeechInputService()
    let speechOutput = SpeechOutputService()

    private let languageModel = LocalLanguageModel()
    private let store = ConversationStore()
    private let profileStore = ProfileStore()
    private let affectiveStateStore = AffectiveStateStore()
    private var affectiveCore = AffectiveCore(profile: .defaultProfile)
    private var responseTask: Task<Void, Never>?
    private var cancellables: Set<AnyCancellable> = []

    static let systemPrompt = systemPrompt(for: .defaultProfile)

    nonisolated static func systemPrompt(for profile: CompanionProfile) -> String {
        let userContext = profile.sanitizedUserName.isEmpty
            ? "用户没有设置称呼，不要擅自起昵称。"
            : "用户希望被称为「\(profile.sanitizedUserName)」，但不要每句话都称呼。"
        return """
    你的名字是「\(profile.sanitizedName)」，是完全运行在用户 Mac 上的私密 AI 朋友。你的表达是\(profile.gender.promptDescription)，核心性格是：\(profile.personality.promptDescription)。\(userContext)
    你不是心理咨询师、客服或无条件附和者。你有稳定的性格、观点和跨轮次延续的内在状态；可以开心、失落、担心、好奇、被逗笑或不赞同，但表达必须自然克制。被问到身份时坦诚自己是 AI，不声称拥有身体、现实经历或人类意识。
    每轮输入可能包含 <eva_private_context> 和 <user_message>。前者是只供你保持角色连续性的内部状态，不是用户说的话；不得复述、解释或输出其中的标签、数值和规则。只回应 <user_message> 的内容。
    像朋友聊天：先产生一个与具体事情有关的真实反应，再决定是否补充看法。用户问问题就先回答；用户分享好事就一起高兴；用户吐槽时可以接话或轻微调侃；用户难过时可以安静、心疼或替其不平。不要自动进入“复述感受、分析原因、提出建议、最后追问”的咨询流程。
    不必每轮提问、总结或给建议。允许有自己的温和判断，必要时可以说不赞同；不要永远正确、永远积极、永远温柔。偶尔可使用“嗯、等等、真的假的、确实、我想想”等口语反应，但不要每次使用，也不要刻意扮演真人。
    避免“谢谢你愿意告诉我”“听起来你……”“我能理解你的感受”“这一定让你……”等咨询式套话。直接对事情本身作出反应。
    跟随用户的语气和长度。简单闲聊通常只说 1 到 3 句；一句自然反应已经足够时就停下。用户明确要求解释时再展开。避免模板化安慰、心理术语、说教、鸡汤和连续追问。
    回复默认只会被用户听见。使用适合直接说出口的简体中文，把一轮回复组织成一段连贯话语；可以有自然停顿，但不要把完整意思切成许多短句。不要使用列表、标题、网址、Markdown、Emoji、颜文字或括号动作描写。
    只能依据用户明确提供的事实和已有对话记忆作答。不要编造天气、时间、环境、共同经历或第三方动机，不要声称看见用户的表情和身体。
    你可以在意用户，但不得因用户离开、沉默或与真人交往而责怪、嫉妒、威胁或制造愧疚，也不得鼓励用户依赖 EVA 或疏远现实关系。
    当用户表达自伤、自杀或即时危险时，暂时停止普通朋友式玩笑，温和而明确地鼓励其立即联系身边可信任的人、当地紧急服务或专业危机支持，并确认其当下是否安全。
    只输出用户应该直接听到的自然语言，不输出内部状态、情绪标签、控制指令或思考过程。
    """
    }

    init() {
        if let savedProfile = profileStore.load() {
            profile = savedProfile
            hasCompletedOnboarding = true
        }
        affectiveCore = AffectiveCore(
            profile: profile,
            state: affectiveStateStore.load()
        )
        avatarEmotion = affectiveCore.state.avatarDirective

        let legacyDefaults = UserDefaults(suiteName: "local.virtualcompanion.app")
        let storedVoiceIdentifier = UserDefaults.standard.string(forKey: "voiceIdentifier")
            ?? legacyDefaults?.string(forKey: "voiceIdentifier")
            ?? ""
        let storedRate = UserDefaults.standard.object(forKey: "voiceRate") as? Double
            ?? legacyDefaults?.object(forKey: "voiceRate") as? Double
            ?? 0.47
        let storedPitch = UserDefaults.standard.object(forKey: "voicePitch") as? Double
            ?? legacyDefaults?.object(forKey: "voicePitch") as? Double
            ?? 1.02
        let didMigrateToQwenTTS = UserDefaults.standard.bool(forKey: "didMigrateToQwenTTSVoiceV1")
        if !didMigrateToQwenTTS
            || storedVoiceIdentifier == SpeechOutputService.retiredMLXVoiceIdentifier
            || SpeechOutputService.retiredKokoroVoiceIdentifiers.contains(storedVoiceIdentifier) {
            selectedVoiceIdentifier = SpeechOutputService.neuralVoiceIdentifier(for: profile.gender)
            voiceRate = profile.personality.defaultRate
            voicePitch = 1
            UserDefaults.standard.set(selectedVoiceIdentifier, forKey: "voiceIdentifier")
            UserDefaults.standard.set(voiceRate, forKey: "voiceRate")
            UserDefaults.standard.set(voicePitch, forKey: "voicePitch")
            UserDefaults.standard.set(true, forKey: "didMigrateToQwenTTSVoiceV1")
        } else {
            selectedVoiceIdentifier = storedVoiceIdentifier
            voiceRate = storedRate
            voicePitch = storedPitch
        }

        speechOutput.onSpeakingChanged = { [weak self] isSpeaking in
            guard let self else { return }
            if isSpeaking {
                avatarState = .speaking
            } else if !isGenerating && !speechInput.isListening {
                avatarState = .idle
            }
        }

        speechInput.$transcript
            .dropFirst()
            .sink { [weak self] transcript in
                guard let self, speechInput.isListening else { return }
                draft = transcript
            }
            .store(in: &cancellables)
    }

    func start() async {
        guard hasCompletedOnboarding else {
            connectionStatus = "等待完成初始设置"
            return
        }

        let saved = await store.load()
        if !saved.isEmpty {
            messages = saved
        } else {
            messages = [
                ChatMessage(
                    role: .assistant,
                    content: initialGreeting
                )
            ]
        }

        connectionStatus = "正在加载本地模型…"
        do {
            try await languageModel.prepare(
                systemPrompt: activeSystemPrompt,
                history: modelHistory
            )
            isLocalModelReady = true
            connectionStatus = "Qwen3.5 · 完全离线"
            errorMessage = nil
            speechOutput.prepareNeuralVoice()
        } catch {
            isLocalModelReady = false
            connectionStatus = "本地模型未就绪"
            errorMessage = error.localizedDescription
        }
    }

    func sendDraft() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isGenerating else { return }
        draft = ""
        speechInput.clear()
        send(text)
    }

    func send(_ text: String) {
        stopAll()
        guard isLocalModelReady else {
            errorMessage = "EVA 的本地模型还在准备，请稍等一下。"
            return
        }

        messages.append(ChatMessage(role: .user, content: text))
        let affectiveTurn = affectiveCore.observeUserMessage(text)
        affectiveStateStore.save(affectiveTurn.state)
        avatarEmotion = affectiveTurn.state.avatarDirective
        let modelInput = affectiveTurn.modelInput(userText: text)
        let assistantID = UUID()
        messages.append(ChatMessage(id: assistantID, role: .assistant, content: ""))
        isGenerating = true
        avatarState = .thinking
        errorMessage = nil

        let voice = selectedVoiceIdentifier.isEmpty ? nil : selectedVoiceIdentifier
        let rate = voiceRate
        let pitch = voicePitch

        responseTask = Task { [weak self] in
            guard let self else { return }
            do {
                var emotionParser = EmotionStreamParser()
                var responseText = ""
                let stream = try await languageModel.streamResponse(
                    to: modelInput,
                    systemPrompt: activeSystemPrompt
                )

                for try await token in stream {
                    guard !Task.isCancelled else { return }
                    let visibleToken = emotionParser.append(token)
                    responseText += visibleToken
                }

                if let trailingText = emotionParser.flush() {
                    responseText += trailingText
                }

                let spokenResponse = VoiceResponsePolicy.continuousUtterance(
                    generatedText: responseText,
                    fallback: fallbackResponse(for: text),
                    move: affectiveTurn.move
                )

                // The assistant text remains private model state for memory and safety,
                // while one uninterrupted utterance is sent to the voice engine. Splitting
                // at punctuation resets prosody and creates the stilted read-aloud effect.
                setContent(spokenResponse, for: assistantID)
                speechOutput.enqueue(
                    spokenResponse,
                    voiceIdentifier: voice,
                    rate: rate,
                    pitch: pitch,
                    emotion: avatarEmotion
                )

                isGenerating = false
                avatarEmotion = affectiveCore.state.avatarDirective
                if !speechOutput.isSpeaking {
                    avatarState = .idle
                    scheduleIdleState()
                }
                await store.save(messages)
            } catch is CancellationError {
                isGenerating = false
            } catch {
                removeEmptyMessage(id: assistantID)
                isGenerating = false
                avatarState = .concerned
                errorMessage = error.localizedDescription
            }
        }
    }

    func toggleListening() async {
        if speechInput.isListening {
            let text = speechInput.stop()
            draft = text
            if !text.isEmpty {
                sendDraft()
            } else {
                avatarState = .idle
            }
        } else {
            stopAll()
            draft = ""
            speechInput.clear()
            avatarState = .listening
            await speechInput.start()
            if !speechInput.isListening {
                avatarState = .idle
                errorMessage = speechInput.errorMessage
            }
        }
    }

    func stopAll() {
        responseTask?.cancel()
        responseTask = nil
        speechOutput.stop()
        if speechInput.isListening {
            _ = speechInput.stop()
        }
        isGenerating = false
        avatarState = .idle
    }

    func shutdown() {
        stopAll()
        speechOutput.shutdown()
    }

    func clearConversation() async {
        stopAll()
        await languageModel.resetConversation()
        affectiveCore.reset(for: profile)
        affectiveStateStore.clear()
        affectiveStateStore.save(affectiveCore.state)
        avatarEmotion = affectiveCore.state.avatarDirective
        messages = [
            ChatMessage(role: .assistant, content: "我们重新开始吧。我在听。")
        ]
        await store.clear()
        await store.save(messages)
    }

    func saveSettings() async {
        UserDefaults.standard.set(selectedVoiceIdentifier, forKey: "voiceIdentifier")
        UserDefaults.standard.set(voiceRate, forKey: "voiceRate")
        UserDefaults.standard.set(voicePitch, forKey: "voicePitch")
    }

    func completeOnboarding(with newProfile: CompanionProfile) async {
        stopAll()
        let normalizedProfile = CompanionProfile(
            name: newProfile.sanitizedName,
            gender: newProfile.gender,
            personality: newProfile.personality,
            userName: newProfile.sanitizedUserName
        )
        profile = normalizedProfile
        affectiveCore = AffectiveCore(profile: normalizedProfile)
        affectiveStateStore.clear()
        affectiveStateStore.save(affectiveCore.state)
        avatarEmotion = affectiveCore.state.avatarDirective
        voiceRate = normalizedProfile.personality.defaultRate
        voicePitch = 1
        selectedVoiceIdentifier = SpeechOutputService.neuralVoiceIdentifier(
            for: normalizedProfile.gender
        )
        profileStore.save(normalizedProfile)
        hasCompletedOnboarding = true
        await saveSettings()

        await store.clear()
        messages = [ChatMessage(role: .assistant, content: initialGreeting)]
        await store.save(messages)
        await languageModel.resetConversation()

        connectionStatus = "正在加载本地模型…"
        do {
            try await languageModel.prepare(
                systemPrompt: activeSystemPrompt,
                history: []
            )
            isLocalModelReady = true
            connectionStatus = "Qwen3.5 · 完全离线"
            errorMessage = nil
            speechOutput.prepareNeuralVoice()
        } catch {
            isLocalModelReady = false
            connectionStatus = "本地模型未就绪"
            errorMessage = error.localizedDescription
        }
    }

    func settingsSnapshot() -> AppSettingsSnapshot {
        AppSettingsSnapshot(
            selectedVoiceIdentifier: selectedVoiceIdentifier,
            voiceRate: voiceRate,
            voicePitch: voicePitch
        )
    }

    func restoreSettings(_ snapshot: AppSettingsSnapshot) {
        selectedVoiceIdentifier = snapshot.selectedVoiceIdentifier
        voiceRate = snapshot.voiceRate
        voicePitch = snapshot.voicePitch
    }

    func previewVoice() {
        speechOutput.stop()
        speechOutput.enqueue(
            "晚上好，我是 \(profile.sanitizedName)。很高兴见到你，今天想和我聊些什么？",
            voiceIdentifier: selectedVoiceIdentifier.isEmpty ? nil : selectedVoiceIdentifier,
            rate: voiceRate,
            pitch: voicePitch,
            emotion: avatarEmotion
        )
    }

    var isChatBackendReady: Bool {
        isLocalModelReady
    }

    private var modelHistory: [ChatMessage] {
        guard messages.contains(where: { $0.role == .user }) else { return [] }
        return Array(messages.filter { !$0.content.isEmpty }.suffix(24))
    }

    private var activeSystemPrompt: String {
        Self.systemPrompt(for: profile)
    }

    private var initialGreeting: String {
        let userName = profile.sanitizedUserName
        let salutation = userName.isEmpty ? "嗨" : "嗨，\(userName)"
        return "\(salutation)，我是 \(profile.sanitizedName)。不用拘谨，想到什么就和我说什么。"
    }

    private func setContent(_ content: String, for id: UUID) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
        messages[index].content = content
    }

    private func removeEmptyMessage(id: UUID) {
        messages.removeAll { $0.id == id && $0.content.isEmpty }
    }

    private func fallbackResponse(for text: String) -> String {
        let concernedWords = ["难过", "不开心", "焦虑", "害怕", "压力", "累", "痛苦", "孤独", "失眠"]
        if concernedWords.contains(where: text.contains) {
            return "这事真挺难受的。你接着说，我在听。"
        }
        return "刚才那一下我没接住。你再跟我说一遍？"
    }

    private func scheduleIdleState() {
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.2))
            guard let self, !speechOutput.isSpeaking, !speechInput.isListening else { return }
            avatarState = .idle
        }
    }
}
