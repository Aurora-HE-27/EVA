import AppKit
import AVFoundation
import Combine
import Foundation
import UniformTypeIdentifiers

@MainActor
final class AppState: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var draft = ""
    @Published var models: [OllamaModel] = []
    @Published var selectedModel = ""
    @Published var serverAddress = "http://127.0.0.1:11434"
    @Published var chatBackend: ChatBackendKind = .ollama
    @Published var apiEndpointAddress = "https://api.openai.com/v1/chat/completions"
    @Published var apiModelName = ""
    @Published var apiKey = ""
    @Published var selectedVoiceIdentifier = ""
    @Published var voiceRate = 0.47
    @Published var voicePitch = 1.02
    @Published var avatarImagePath = ""
    @Published var avatarState: AvatarState = .idle
    @Published var avatarEmotion: EmotionDirective = .neutral
    @Published var isGenerating = false
    @Published var connectionStatus = "正在连接 Ollama…"
    @Published var errorMessage: String?
    @Published var showsSettings = false

    let speechInput = SpeechInputService()
    let speechOutput = SpeechOutputService()

    private let ollama = OllamaClient()
    private let compatibleAPI = OpenAICompatibleClient()
    private let store = ConversationStore()
    private var responseTask: Task<Void, Never>?
    private var cancellables: Set<AnyCancellable> = []

    private let systemPrompt = """
    你的名字是 EVA，是一位运行在用户 Mac 上的本地虚拟伴侣。你温暖、自然、有边界感，也会坦诚自己是 AI。
    使用简体中文口语化交流，通常回答 1 到 4 句，除非用户明确要求详细解释。
    不要用 Markdown 标题，不要在每句话都称呼用户，不要假装拥有现实世界的身体经历。
    当用户情绪低落时先倾听，不要过度说教，也不要鼓励用户依赖或疏远真实的人际关系。
    每次回复必须先输出一行不可省略的表情控制指令，然后换行输出给用户看的正文。
    指令格式严格为：[[EVA emotion=warm valence=0.3 arousal=0.2 intensity=0.5]]
    emotion 只能是 neutral、warm、happy、concerned、sad、surprised、focused 之一；valence 范围 -1 到 1，arousal 和 intensity 范围 0 到 1。
    指令只描述 EVA 此刻应该呈现的情绪，不要复述或解释指令。
    """

    init() {
        let legacyDefaults = UserDefaults(suiteName: "local.virtualcompanion.app")
        selectedModel = UserDefaults.standard.string(forKey: "selectedModel")
            ?? legacyDefaults?.string(forKey: "selectedModel")
            ?? ""
        serverAddress = UserDefaults.standard.string(forKey: "serverAddress")
            ?? legacyDefaults?.string(forKey: "serverAddress")
            ?? "http://127.0.0.1:11434"
        chatBackend = UserDefaults.standard.string(forKey: "chatBackend")
            .flatMap(ChatBackendKind.init(rawValue:))
            ?? .ollama
        apiEndpointAddress = UserDefaults.standard.string(forKey: "apiEndpointAddress")
            ?? "https://api.openai.com/v1/chat/completions"
        apiModelName = UserDefaults.standard.string(forKey: "apiModelName") ?? ""
        apiKey = KeychainStore.loadAPIKey()
        let storedVoiceIdentifier = UserDefaults.standard.string(forKey: "voiceIdentifier")
            ?? legacyDefaults?.string(forKey: "voiceIdentifier")
            ?? ""
        let didMigrateToVoiceDesign = UserDefaults.standard.bool(
            forKey: "didMigrateToQwenVoiceDesign"
        )
        let usesDefaultVoice = storedVoiceIdentifier.isEmpty || !didMigrateToVoiceDesign
        selectedVoiceIdentifier = usesDefaultVoice
            ? SpeechOutputService.evaVoiceIdentifier
            : storedVoiceIdentifier
        voiceRate = usesDefaultVoice
            ? 0.46
            : UserDefaults.standard.object(forKey: "voiceRate") as? Double
                ?? legacyDefaults?.object(forKey: "voiceRate") as? Double
                ?? 0.46
        voicePitch = usesDefaultVoice
            ? 1.06
            : UserDefaults.standard.object(forKey: "voicePitch") as? Double
                ?? legacyDefaults?.object(forKey: "voicePitch") as? Double
                ?? 1.06

        let storedAvatarPath = UserDefaults.standard.string(forKey: "avatarImagePath")
            ?? legacyDefaults?.string(forKey: "avatarImagePath")
            ?? ""
        avatarImagePath = storedAvatarPath.isEmpty ? Self.bundledAvatarPath : storedAvatarPath

        if usesDefaultVoice {
            UserDefaults.standard.set(selectedVoiceIdentifier, forKey: "voiceIdentifier")
            UserDefaults.standard.set(voiceRate, forKey: "voiceRate")
            UserDefaults.standard.set(voicePitch, forKey: "voicePitch")
            UserDefaults.standard.set(true, forKey: "didMigrateToQwenVoiceDesign")
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
        let saved = await store.load()
        if !saved.isEmpty {
            messages = saved
        } else {
            messages = [
                ChatMessage(
                    role: .assistant,
                    content: "你好，我是 EVA。我已经在这台 Mac 上醒来了，想先聊聊什么？"
                )
            ]
        }
        await refreshModels()
    }

    func refreshModels() async {
        guard chatBackend == .ollama else {
            let configured = !apiEndpointAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && !apiModelName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            connectionStatus = configured
                ? "大模型 API 已配置 · \(apiModelName)"
                : "大模型 API 尚未配置完整"
            errorMessage = configured ? nil : AppError.incompleteAPIConfiguration.localizedDescription
            return
        }

        do {
            let url = try ollamaServerURL()
            models = try await ollama.models(serverURL: url)
            connectionStatus = models.isEmpty ? "Ollama 已连接，但没有模型" : "Ollama 已连接"
            errorMessage = nil

            let modelIsUnavailable = !models.contains(where: { $0.name == selectedModel })
            let shouldMigrateBrokenQwen = Self.isBrokenUpstreamQwenModel(selectedModel)
                && models.contains(where: { Self.isEVAModel($0.name) })

            if selectedModel.isEmpty || modelIsUnavailable || shouldMigrateBrokenQwen {
                selectedModel = preferredModel(from: models) ?? ""
                UserDefaults.standard.set(selectedModel, forKey: "selectedModel")
            }
        } catch {
            models = []
            connectionStatus = "无法连接 Ollama"
            errorMessage = friendlyConnectionError(error)
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
        if chatBackend == .ollama {
            guard !selectedModel.isEmpty else {
                errorMessage = AppError.noModel.localizedDescription
                showsSettings = true
                return
            }
        } else {
            guard !apiEndpointAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !apiModelName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                errorMessage = AppError.incompleteAPIConfiguration.localizedDescription
                showsSettings = true
                return
            }
        }

        let userMessage = ChatMessage(role: .user, content: text)
        messages.append(userMessage)
        let assistantID = UUID()
        messages.append(
            ChatMessage(id: assistantID, role: .assistant, content: "")
        )
        isGenerating = true
        avatarState = .thinking
        errorMessage = nil

        let history = apiMessages()
        let backend = chatBackend
        let model = selectedModel
        let endpointAddress = apiEndpointAddress
        let remoteModel = apiModelName
        let remoteAPIKey = apiKey
        let voice = selectedVoiceIdentifier.isEmpty ? nil : selectedVoiceIdentifier
        let rate = voiceRate
        let pitch = voicePitch

        responseTask = Task { [weak self] in
            guard let self else { return }
            do {
                var segmenter = SentenceSegmenter()
                var emotionParser = EmotionStreamParser()
                var receivedContent = false

                let attempts = backend == .ollama ? 2 : 1
                for attempt in 0..<attempts {
                    let stream: AsyncThrowingStream<String, Error>
                    if backend == .ollama {
                        stream = ollama.streamChat(
                            serverURL: try ollamaServerURL(),
                            model: model,
                            messages: history
                        )
                    } else {
                        stream = compatibleAPI.streamChat(
                            endpointURL: try compatibleAPIURL(from: endpointAddress),
                            apiKey: remoteAPIKey,
                            model: remoteModel,
                            messages: history
                        )
                    }

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
                                emotion: avatarEmotion.emotion
                            )
                        }
                    }

                    if receivedContent {
                        break
                    }
                    if attempt + 1 < attempts {
                        emotionParser = EmotionStreamParser()
                        segmenter = SentenceSegmenter()
                        try await Task.sleep(for: .milliseconds(250))
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
                            emotion: avatarEmotion.emotion
                        )
                    }
                }

                if let remainder = segmenter.flush() {
                    speechOutput.enqueue(
                        remainder,
                        voiceIdentifier: voice,
                        rate: rate,
                        pitch: pitch,
                        emotion: avatarEmotion.emotion
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
        avatarEmotion = .neutral
        messages = [
            ChatMessage(role: .assistant, content: "我们重新开始吧。我在听。")
        ]
        await store.clear()
        await store.save(messages)
    }

    func saveSettings() async {
        UserDefaults.standard.set(chatBackend.rawValue, forKey: "chatBackend")
        UserDefaults.standard.set(selectedModel, forKey: "selectedModel")
        UserDefaults.standard.set(serverAddress, forKey: "serverAddress")
        UserDefaults.standard.set(apiEndpointAddress, forKey: "apiEndpointAddress")
        UserDefaults.standard.set(apiModelName, forKey: "apiModelName")
        UserDefaults.standard.set(selectedVoiceIdentifier, forKey: "voiceIdentifier")
        UserDefaults.standard.set(voiceRate, forKey: "voiceRate")
        UserDefaults.standard.set(voicePitch, forKey: "voicePitch")
        UserDefaults.standard.set(avatarImagePath, forKey: "avatarImagePath")
        do {
            try KeychainStore.saveAPIKey(apiKey)
        } catch {
            errorMessage = error.localizedDescription
            return
        }
        await refreshModels()
    }

    func settingsSnapshot() -> AppSettingsSnapshot {
        AppSettingsSnapshot(
            chatBackend: chatBackend,
            selectedModel: selectedModel,
            serverAddress: serverAddress,
            apiEndpointAddress: apiEndpointAddress,
            apiModelName: apiModelName,
            apiKey: apiKey,
            selectedVoiceIdentifier: selectedVoiceIdentifier,
            voiceRate: voiceRate,
            voicePitch: voicePitch,
            avatarImagePath: avatarImagePath
        )
    }

    func restoreSettings(_ snapshot: AppSettingsSnapshot) {
        chatBackend = snapshot.chatBackend
        selectedModel = snapshot.selectedModel
        serverAddress = snapshot.serverAddress
        apiEndpointAddress = snapshot.apiEndpointAddress
        apiModelName = snapshot.apiModelName
        apiKey = snapshot.apiKey
        selectedVoiceIdentifier = snapshot.selectedVoiceIdentifier
        voiceRate = snapshot.voiceRate
        voicePitch = snapshot.voicePitch
        avatarImagePath = snapshot.avatarImagePath

        // Avatar import predates transactional settings and persists immediately.
        // Restore its saved value as well when the user cancels this sheet.
        UserDefaults.standard.set(snapshot.avatarImagePath, forKey: "avatarImagePath")
    }

    func previewVoice() {
        speechOutput.stop()
        speechOutput.enqueue(
            "晚上好，我是 EVA。很高兴见到你，今天想和我聊些什么？",
            voiceIdentifier: selectedVoiceIdentifier.isEmpty ? nil : selectedVoiceIdentifier,
            rate: voiceRate,
            pitch: voicePitch,
            emotion: avatarEmotion.emotion
        )
    }

    var avatarDisplayName: String {
        guard !avatarImagePath.isEmpty else { return "尚未导入" }
        return avatarImagePath == Self.bundledAvatarPath ? "EVA 原创形象" : "自定义形象"
    }

    func useBundledAvatar() {
        avatarImagePath = Self.bundledAvatarPath
        UserDefaults.standard.set(avatarImagePath, forKey: "avatarImagePath")
    }

    func chooseAvatarImage() {
        let panel = NSOpenPanel()
        panel.title = "选择原创或已获授权的成年人物肖像"
        panel.prompt = "使用此形象"
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.png, .jpeg, .heic]

        guard panel.runModal() == .OK, let source = panel.url else { return }

        do {
            let support = FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first!
            let directory = support.appending(
                path: "EVA/Avatar",
                directoryHint: .isDirectory
            )
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            let ext = source.pathExtension.isEmpty ? "png" : source.pathExtension
            let destination = directory.appending(path: "companion.\(ext)")

            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: source, to: destination)
            avatarImagePath = destination.path
            UserDefaults.standard.set(avatarImagePath, forKey: "avatarImagePath")
            errorMessage = nil
        } catch {
            errorMessage = "导入角色图片失败：\(error.localizedDescription)"
        }
    }

    var isChatBackendReady: Bool {
        switch chatBackend {
        case .ollama:
            !selectedModel.isEmpty && !models.isEmpty
        case .compatibleAPI:
            !apiEndpointAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && !apiModelName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private func apiMessages() -> [ChatAPIMessage] {
        var result = [
            ChatAPIMessage(role: "system", content: systemPrompt)
        ]
        result += messages
            .filter { !$0.content.isEmpty }
            .suffix(24)
            .map {
                ChatAPIMessage(role: $0.role.rawValue, content: $0.content)
            }
        return result
    }

    private static var bundledAvatarPath: String {
        Bundle.main.path(
            forResource: "EVA-Portrait-Young-v1",
            ofType: "png",
            inDirectory: "Assets"
        ) ?? ""
    }

    private func append(_ token: String, to id: UUID) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
        messages[index].content += token
    }

    private func removeEmptyMessage(id: UUID) {
        messages.removeAll { $0.id == id && $0.content.isEmpty }
    }

    private func ollamaServerURL() throws -> URL {
        guard let url = URL(string: serverAddress),
              let scheme = url.scheme,
              ["http", "https"].contains(scheme),
              url.host != nil else {
            throw AppError.invalidServerURL
        }
        return url
    }

    private func compatibleAPIURL(from address: String) throws -> URL {
        guard let url = URL(string: address.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = url.scheme,
              scheme == "https",
              url.host != nil else {
            throw AppError.invalidAPIURL
        }
        return url
    }

    private func preferredModel(from models: [OllamaModel]) -> String? {
        if let eva = models.first(where: { Self.isEVAModel($0.name) }) {
            return eva.name
        }

        let preferences = ["qwen", "gemma", "llama"]
        for prefix in preferences {
            if let model = models.first(where: { $0.name.lowercased().contains(prefix) }) {
                return model.name
            }
        }
        return models.first?.name
    }

    private static func isEVAModel(_ name: String) -> Bool {
        let normalized = name.lowercased()
        return normalized == "eva" || normalized.hasPrefix("eva:")
    }

    private static func isBrokenUpstreamQwenModel(_ name: String) -> Bool {
        name.lowercased().contains("mradermacher/qwen3-14b-uncensored-gguf")
    }

    private func friendlyConnectionError(_ error: Error) -> String {
        if let urlError = error as? URLError,
           [.cannotConnectToHost, .networkConnectionLost, .timedOut].contains(urlError.code) {
            return "连接不到 Ollama。请先打开 Ollama 应用，确认服务地址为 \(serverAddress)。"
        }
        return error.localizedDescription
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
