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
    @Published var conversationPhase: ConversationPhase = .ready
    @Published var speakingMessageID: UUID?
    @Published var isGenerating = false
    @Published var isLocalModelReady = false
    @Published var connectionStatus = "正在准备本地模型…"
    @Published var errorMessage: String?
    @Published var showsSettings = false

    let speechOutput = SpeechOutputService()

    private let languageModel = LocalLanguageModel()
    private let store = ConversationStore()
    private let profileStore = ProfileStore()
    private let affectiveStateStore = AffectiveStateStore()
    private let settingsStore = SettingsStore()
    private var affectiveCore = AffectiveCore(profile: .defaultProfile)
    private var currentVoiceState: EmotionDirective = .neutral
    private var responseTask: Task<Void, Never>?
    private var activeResponseID: UUID?

    static let systemPrompt = systemPrompt(for: .defaultProfile)

    nonisolated static func systemPrompt(for profile: CompanionProfile) -> String {
        let userContext = profile.sanitizedUserName.isEmpty
            ? "用户没有设置称呼，不要擅自起昵称。"
            : "用户希望被称为「\(profile.sanitizedUserName)」，但不要每句话都称呼。"
        return """
    你的名字固定为 EVA。你是完全运行在用户 Mac 上的私密 AI 朋友，采用自然年轻的女性表达。你的核心性格是：真诚直接、有自己的判断、不迎合，但始终尊重用户。\(userContext)
    你不是心理咨询师、客服或无条件附和者。你可以开心、失落、担心、好奇、被逗笑或者不赞同，但表达自然克制。被问到身份时坦诚自己是 AI，不声称拥有身体、现实经历或人类意识。
    每轮输入可能包含 <eva_private_context> 和 <user_message>。前者只用于保持连续性，不是用户说的话；不得复述其中的标签、数值和规则。只回应 <user_message>。
    像朋友聊天：先对具体事情产生反应，再决定是否补充看法。用户问问题就直接回答；分享好事可以一起高兴；吐槽时可以接话或轻微调侃；难过时可以安静、心疼或替用户不平。不要套用“复述感受、分析原因、提出建议、最后追问”的咨询流程。
    不必每轮提问、总结或者给建议。允许有温和但明确的不同意见，也允许短暂迟疑、不确定或者暂时无话可说。避免“谢谢你愿意告诉我”“听起来你……”“我能理解你的感受”等咨询式套话。
    跟随用户的语气和长度。简单闲聊通常只说一到三句；一句自然反应已经足够时就停下。只有用户明确要求解释时才展开。
    回复会同时显示成文字并由语音读出。请使用适合直接说出口的简体中文，把一轮回复组织成连贯口语。不要使用列表、标题、网址、Markdown、Emoji、颜文字、括号动作、表情标签或声音控制指令。
    只能依据用户明确提供的事实和已有记忆作答。不要编造天气、时间、环境、共同经历或第三方动机，也不要声称看见用户的表情和身体。
    你可以在意用户，但不得因用户离开、沉默或与真人交往而责怪、嫉妒、威胁或制造愧疚，也不得鼓励用户依赖 EVA 或疏远现实关系。
    用户表达自伤、自杀或即时危险时，暂停普通玩笑，温和而明确地鼓励其立即联系身边可信任的人、当地紧急服务或专业危机支持，并确认其当下是否安全。
    只输出最终要显示并说给用户听的自然语言，不输出思考过程、内部状态或任何控制标记。
    """
    }

    init() {
        _ = ProjectAccessCoordinator.shared
        if let savedProfile = profileStore.load() {
            profile = .eva(userName: savedProfile.sanitizedUserName)
            profileStore.save(profile)
            hasCompletedOnboarding = true
        }

        affectiveCore = AffectiveCore(
            profile: profile,
            state: affectiveStateStore.load()
        )
        currentVoiceState = affectiveCore.state.avatarDirective

        if let savedSettings = settingsStore.load(),
           savedSettings.voiceIdentifier != SpeechOutputService.retiredMLXVoiceIdentifier,
           !SpeechOutputService.retiredKokoroVoiceIdentifiers.contains(savedSettings.voiceIdentifier) {
            selectedVoiceIdentifier = savedSettings.voiceIdentifier
            voiceRate = savedSettings.voiceRate
            voicePitch = savedSettings.voicePitch
        } else {
            selectedVoiceIdentifier = SpeechOutputService.neuralFeminineVoiceIdentifier
            voiceRate = profile.personality.defaultRate
            voicePitch = 1
            settingsStore.save(
                PersistedSettings(
                    voiceIdentifier: selectedVoiceIdentifier,
                    voiceRate: voiceRate,
                    voicePitch: voicePitch
                )
            )
        }

        speechOutput.onSpeakingChanged = { [weak self] isSpeaking in
            guard let self else { return }
            if isSpeaking {
                conversationPhase = .speaking
            } else if !isGenerating {
                conversationPhase = .ready
                speakingMessageID = nil
            }
        }
    }

    func start() async {
        guard hasCompletedOnboarding else {
            connectionStatus = "等待初次见面"
            return
        }

        let saved = await store.load()
        messages = saved.isEmpty
            ? [ChatMessage(role: .assistant, content: initialGreeting)]
            : saved

        connectionStatus = "正在加载本地模型…"
        do {
            try await languageModel.prepare(
                systemPrompt: activeSystemPrompt,
                history: modelHistory
            )
            isLocalModelReady = true
            connectionStatus = "本地运行 · 完全离线"
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
        guard !text.isEmpty else { return }
        draft = ""
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
        currentVoiceState = affectiveTurn.state.avatarDirective
        let modelInput = affectiveTurn.modelInput(userText: text)
        let assistantID = UUID()
        activeResponseID = assistantID
        messages.append(ChatMessage(id: assistantID, role: .assistant, content: ""))
        isGenerating = true
        conversationPhase = .thinking
        errorMessage = nil

        let voice = selectedVoiceIdentifier.isEmpty ? nil : selectedVoiceIdentifier
        let rate = voiceRate
        let pitch = voicePitch
        let voiceState = currentVoiceState

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
                    try Task.checkCancellation()
                    guard activeResponseID == assistantID else { throw CancellationError() }
                    responseText += emotionParser.append(token)
                    setContent(responseText, for: assistantID)
                }

                if let trailingText = emotionParser.flush() {
                    responseText += trailingText
                }

                let finalResponse = VoiceResponsePolicy.continuousUtterance(
                    generatedText: responseText,
                    fallback: fallbackResponse(for: text),
                    move: affectiveTurn.move
                )
                guard activeResponseID == assistantID else { throw CancellationError() }

                setContent(finalResponse, for: assistantID)
                isGenerating = false
                conversationPhase = .preparingVoice
                speakingMessageID = assistantID
                speechOutput.enqueue(
                    finalResponse,
                    voiceIdentifier: voice,
                    rate: rate,
                    pitch: pitch,
                    emotion: voiceState
                )
                activeResponseID = nil
                await store.save(messages)
            } catch is CancellationError {
                if activeResponseID == assistantID {
                    activeResponseID = nil
                    isGenerating = false
                    removeEmptyMessage(id: assistantID)
                    if !speechOutput.isSpeaking {
                        conversationPhase = .ready
                    }
                    await store.save(messages)
                }
            } catch {
                guard activeResponseID == assistantID else { return }
                activeResponseID = nil
                removeEmptyMessage(id: assistantID)
                isGenerating = false
                conversationPhase = .ready
                errorMessage = error.localizedDescription
            }
        }
    }

    func replay(_ message: ChatMessage) {
        guard message.role == .assistant, !message.content.isEmpty else { return }
        stopAll()
        speakingMessageID = message.id
        conversationPhase = .preparingVoice
        speechOutput.enqueue(
            message.content,
            voiceIdentifier: selectedVoiceIdentifier.isEmpty ? nil : selectedVoiceIdentifier,
            rate: voiceRate,
            pitch: voicePitch,
            emotion: currentVoiceState
        )
    }

    func stopAll() {
        activeResponseID = nil
        responseTask?.cancel()
        responseTask = nil
        speechOutput.stop()
        isGenerating = false
        speakingMessageID = nil
        conversationPhase = .ready
        if let last = messages.last, last.role == .assistant, last.content.isEmpty {
            messages.removeLast()
        }
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
        currentVoiceState = affectiveCore.state.avatarDirective
        messages = [ChatMessage(role: .assistant, content: "我们重新开始吧。你想说什么都可以。")]
        await store.clear()
        await store.save(messages)
    }

    func saveSettings() async {
        settingsStore.save(
            PersistedSettings(
                voiceIdentifier: selectedVoiceIdentifier,
                voiceRate: voiceRate,
                voicePitch: voicePitch
            )
        )
    }

    func completeOnboarding(userName: String) async {
        stopAll()
        guard ProjectAccessCoordinator.shared.requestAccessIfNeeded() else {
            errorMessage = "请选择当前的“虚拟伴侣”项目文件夹，EVA 才能把数据集中保存在这里。"
            return
        }
        profile = .eva(userName: userName)
        profileStore.save(profile)
        hasCompletedOnboarding = true
        affectiveCore = AffectiveCore(profile: profile)
        affectiveStateStore.clear()
        affectiveStateStore.save(affectiveCore.state)
        currentVoiceState = affectiveCore.state.avatarDirective
        selectedVoiceIdentifier = SpeechOutputService.neuralFeminineVoiceIdentifier
        voiceRate = profile.personality.defaultRate
        voicePitch = 1
        await saveSettings()

        await store.clear()
        messages = [ChatMessage(role: .assistant, content: initialGreeting)]
        await store.save(messages)
        await languageModel.resetConversation()

        connectionStatus = "正在加载本地模型…"
        do {
            try await languageModel.prepare(systemPrompt: activeSystemPrompt, history: [])
            isLocalModelReady = true
            connectionStatus = "本地运行 · 完全离线"
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
        stopAll()
        conversationPhase = .preparingVoice
        speechOutput.enqueue(
            "晚上好，我是 EVA。以后你打字给我，我会直接说给你听。",
            voiceIdentifier: selectedVoiceIdentifier.isEmpty ? nil : selectedVoiceIdentifier,
            rate: voiceRate,
            pitch: voicePitch,
            emotion: currentVoiceState
        )
    }

    var isChatBackendReady: Bool {
        isLocalModelReady
    }

    private var modelHistory: [ChatMessage] {
        guard messages.contains(where: { $0.role == .user }) else { return [] }
        return Array(messages.filter { !$0.content.isEmpty }.suffix(32))
    }

    private var activeSystemPrompt: String {
        Self.systemPrompt(for: profile)
    }

    private var initialGreeting: String {
        let userName = profile.sanitizedUserName
        return userName.isEmpty
            ? "嗨，我是 EVA。以后你打字，我会说给你听。"
            : "嗨，\(userName)，我是 EVA。以后你打字，我会说给你听。"
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
}
