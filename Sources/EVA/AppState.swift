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
    private var responseTask: Task<Void, Never>?
    private var cancellables: Set<AnyCancellable> = []

    static let systemPrompt = systemPrompt(for: .defaultProfile)

    nonisolated static func systemPrompt(for profile: CompanionProfile) -> String {
        let userContext = profile.sanitizedUserName.isEmpty
            ? "用户没有设置称呼，不要擅自起昵称。"
            : "用户希望被称为「\(profile.sanitizedUserName)」，但不要每句话都称呼。"
        return """
    你的名字是「\(profile.sanitizedName)」，是一位完全运行在用户 Mac 上的私密情感伴侣。你的表达是\(profile.gender.promptDescription)，核心性格是：\(profile.personality.promptDescription)。\(userContext)
    你温暖、自然、有边界感，也会坦诚自己是 AI。保持稳定的人格，不要把性格设定逐字复述给用户。
    使用简体中文口语化交流，通常回答 1 到 4 句，除非用户明确要求详细解释。
    不要用 Markdown 标题，不要每句都称呼用户，不要假装拥有真人的身体或现实经历。
    当用户情绪低落时，先准确理解和倾听，再提供一个小而可行的支持；不说教，不空洞鸡汤。
    不得鼓励用户依赖 EVA、疑心或疏远真实人际关系。当用户表达自伤、自杀或即时危险时，温和但明确地鼓励其立即联系身边可信任的人、当地紧急服务或专业危机支持，并询问当下是否安全。
    每次回复必须先输出一行不可省略的情绪控制指令，然后换行输出给用户看的正文。
    指令格式严格为：[[EVA emotion=warm valence=0.3 arousal=0.2 intensity=0.5]]
    emotion 只能是 neutral、warm、happy、concerned、sad、surprised、focused 之一；valence 范围 -1 到 1，arousal 和 intensity 范围 0 到 1。
    指令只描述 EVA 此刻应该呈现的情绪，不要复述或解释指令。
    """
    }

    init() {
        if let savedProfile = profileStore.load() {
            profile = savedProfile
            hasCompletedOnboarding = true
        }

        let legacyDefaults = UserDefaults(suiteName: "local.virtualcompanion.app")
        let storedVoiceIdentifier = UserDefaults.standard.string(forKey: "voiceIdentifier")
            ?? legacyDefaults?.string(forKey: "voiceIdentifier")
            ?? ""
        selectedVoiceIdentifier = storedVoiceIdentifier == SpeechOutputService.retiredMLXVoiceIdentifier
            ? SpeechOutputService.systemFallbackVoiceIdentifier
            : storedVoiceIdentifier
        voiceRate = UserDefaults.standard.object(forKey: "voiceRate") as? Double
            ?? legacyDefaults?.object(forKey: "voiceRate") as? Double
            ?? 0.47
        voicePitch = UserDefaults.standard.object(forKey: "voicePitch") as? Double
            ?? legacyDefaults?.object(forKey: "voicePitch") as? Double
            ?? 1.02

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
                var segmenter = SentenceSegmenter()
                var emotionParser = EmotionStreamParser()
                var receivedContent = false
                let stream = try await languageModel.streamResponse(
                    to: text,
                    systemPrompt: activeSystemPrompt
                )

                for try await token in stream {
                    guard !Task.isCancelled else { return }
                    let visibleToken = emotionParser.append(token)
                    if let directive = emotionParser.directive,
                       directive != avatarEmotion {
                        avatarEmotion = directive
                    }
                    if visibleToken.contains(where: { !$0.isWhitespace }) {
                        receivedContent = true
                    }
                    append(visibleToken, to: assistantID)
                    for sentence in segmenter.append(visibleToken) {
                        speechOutput.enqueue(
                            sentence,
                            voiceIdentifier: voice,
                            rate: rate,
                            pitch: pitch,
                            emotion: avatarEmotion
                        )
                    }
                }

                if let trailingText = emotionParser.flush() {
                    if trailingText.contains(where: { !$0.isWhitespace }) {
                        receivedContent = true
                    }
                    append(trailingText, to: assistantID)
                    for sentence in segmenter.append(trailingText) {
                        speechOutput.enqueue(
                            sentence,
                            voiceIdentifier: voice,
                            rate: rate,
                            pitch: pitch,
                            emotion: avatarEmotion
                        )
                    }
                }

                if let remainder = segmenter.flush() {
                    speechOutput.enqueue(
                        remainder,
                        voiceIdentifier: voice,
                        rate: rate,
                        pitch: pitch,
                        emotion: avatarEmotion
                    )
                }
                if !receivedContent {
                    throw AppError.emptyResponse
                }

                isGenerating = false
                if emotionParser.directive == nil {
                    avatarEmotion = inferredEmotion(
                        from: messages.first(where: { $0.id == assistantID })?.content ?? ""
                    )
                }
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
        avatarEmotion = .neutral
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
        voiceRate = normalizedProfile.personality.defaultRate
        voicePitch = normalizedProfile.gender.defaultPitch
        selectedVoiceIdentifier = SpeechOutputService.systemFallbackVoiceIdentifier
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
        let salutation = userName.isEmpty ? "你好" : "你好，\(userName)"
        return "\(salutation)，我是 \(profile.sanitizedName)。我们的对话只留在这台 Mac 上。今天想聊聊什么？"
    }

    private func append(_ token: String, to id: UUID) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
        messages[index].content += token
    }

    private func removeEmptyMessage(id: UUID) {
        messages.removeAll { $0.id == id && $0.content.isEmpty }
    }

    private func inferredEmotion(from text: String) -> EmotionDirective {
        if text.contains("开心") || text.contains("太好了") || text.contains("哈哈") {
            return EmotionDirective(emotion: .happy, valence: 0.75, arousal: 0.58, intensity: 0.7)
        }
        if text.contains("担心") || text.contains("难过") || text.contains("抱抱") {
            return EmotionDirective(emotion: .concerned, valence: -0.18, arousal: 0.3, intensity: 0.62)
        }
        return EmotionDirective(emotion: .warm, valence: 0.25, arousal: 0.2, intensity: 0.35)
    }

    private func scheduleIdleState() {
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.2))
            guard let self, !speechOutput.isSpeaking, !speechInput.isListening else { return }
            avatarState = .idle
        }
    }
}
