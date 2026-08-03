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
    @Published var selectedVoiceIdentifier = ""
    @Published var voiceRate = 0.47
    @Published var voicePitch = 1.02
    @Published var avatarImagePath = ""
    @Published var avatarState: AvatarState = .idle
    @Published var isGenerating = false
    @Published var connectionStatus = "正在连接 Ollama…"
    @Published var errorMessage: String?
    @Published var showsSettings = false

    let speechInput = SpeechInputService()
    let speechOutput = SpeechOutputService()

    private let ollama = OllamaClient()
    private let store = ConversationStore()
    private var responseTask: Task<Void, Never>?
    private var cancellables: Set<AnyCancellable> = []

    private let systemPrompt = """
    你的名字是 EVA，是一位运行在用户 Mac 上的本地虚拟伴侣。你温暖、自然、有边界感，也会坦诚自己是 AI。
    使用简体中文口语化交流，通常回答 1 到 4 句，除非用户明确要求详细解释。
    不要用 Markdown 标题，不要在每句话都称呼用户，不要假装拥有现实世界的身体经历。
    当用户情绪低落时先倾听，不要过度说教，也不要鼓励用户依赖或疏远真实的人际关系。
    """

    init() {
        let legacyDefaults = UserDefaults(suiteName: "local.virtualcompanion.app")
        selectedModel = UserDefaults.standard.string(forKey: "selectedModel")
            ?? legacyDefaults?.string(forKey: "selectedModel")
            ?? ""
        serverAddress = UserDefaults.standard.string(forKey: "serverAddress")
            ?? legacyDefaults?.string(forKey: "serverAddress")
            ?? "http://127.0.0.1:11434"
        selectedVoiceIdentifier = UserDefaults.standard.string(forKey: "voiceIdentifier")
            ?? legacyDefaults?.string(forKey: "voiceIdentifier")
            ?? ""
        voiceRate = UserDefaults.standard.object(forKey: "voiceRate") as? Double
            ?? legacyDefaults?.object(forKey: "voiceRate") as? Double
            ?? 0.47
        voicePitch = UserDefaults.standard.object(forKey: "voicePitch") as? Double
            ?? legacyDefaults?.object(forKey: "voicePitch") as? Double
            ?? 1.02
        avatarImagePath = UserDefaults.standard.string(forKey: "avatarImagePath")
            ?? legacyDefaults?.string(forKey: "avatarImagePath")
            ?? ""

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
        do {
            let url = try serverURL()
            models = try await ollama.models(serverURL: url)
            connectionStatus = models.isEmpty ? "Ollama 已连接，但没有模型" : "Ollama 已连接"
            errorMessage = nil

            if selectedModel.isEmpty || !models.contains(where: { $0.name == selectedModel }) {
                selectedModel = preferredModel(from: models) ?? ""
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
        guard !selectedModel.isEmpty else {
            errorMessage = AppError.noModel.localizedDescription
            showsSettings = true
            return
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
        let model = selectedModel
        let voice = selectedVoiceIdentifier.isEmpty ? nil : selectedVoiceIdentifier
        let rate = voiceRate
        let pitch = voicePitch

        responseTask = Task { [weak self] in
            guard let self else { return }
            do {
                let url = try serverURL()
                var segmenter = SentenceSegmenter()
                var receivedContent = false

                for attempt in 0..<2 {
                    for try await token in ollama.streamChat(
                        serverURL: url,
                        model: model,
                        messages: history
                    ) {
                        guard !Task.isCancelled else { return }
                        if token.contains(where: { !$0.isWhitespace }) {
                            receivedContent = true
                        }
                        append(token, to: assistantID)
                        for sentence in segmenter.append(token) {
                            speechOutput.enqueue(
                                sentence,
                                voiceIdentifier: voice,
                                rate: rate,
                                pitch: pitch
                            )
                        }
                    }

                    if receivedContent {
                        break
                    }
                    if attempt == 0 {
                        try await Task.sleep(for: .milliseconds(250))
                    }
                }

                if let remainder = segmenter.flush() {
                    speechOutput.enqueue(
                        remainder,
                        voiceIdentifier: voice,
                        rate: rate,
                        pitch: pitch
                    )
                }
                if !receivedContent {
                    throw AppError.emptyResponse
                }

                isGenerating = false
                if !speechOutput.isSpeaking {
                    avatarState = inferredEmotion(
                        from: messages.first(where: { $0.id == assistantID })?.content ?? ""
                    )
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

    func clearConversation() async {
        stopAll()
        messages = [
            ChatMessage(role: .assistant, content: "我们重新开始吧。我在听。")
        ]
        await store.clear()
        await store.save(messages)
    }

    func saveSettings() async {
        UserDefaults.standard.set(selectedModel, forKey: "selectedModel")
        UserDefaults.standard.set(serverAddress, forKey: "serverAddress")
        UserDefaults.standard.set(selectedVoiceIdentifier, forKey: "voiceIdentifier")
        UserDefaults.standard.set(voiceRate, forKey: "voiceRate")
        UserDefaults.standard.set(voicePitch, forKey: "voicePitch")
        UserDefaults.standard.set(avatarImagePath, forKey: "avatarImagePath")
        await refreshModels()
    }

    func previewVoice() {
        speechOutput.stop()
        speechOutput.enqueue(
            "晚上好，我会一直认真听你说话。",
            voiceIdentifier: selectedVoiceIdentifier.isEmpty ? nil : selectedVoiceIdentifier,
            rate: voiceRate,
            pitch: voicePitch
        )
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

    private func apiMessages() -> [OllamaClient.APIMessage] {
        var result = [
            OllamaClient.APIMessage(role: "system", content: systemPrompt)
        ]
        result += messages
            .filter { !$0.content.isEmpty }
            .suffix(24)
            .map {
                OllamaClient.APIMessage(role: $0.role.rawValue, content: $0.content)
            }
        return result
    }

    private func append(_ token: String, to id: UUID) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
        messages[index].content += token
    }

    private func removeEmptyMessage(id: UUID) {
        messages.removeAll { $0.id == id && $0.content.isEmpty }
    }

    private func serverURL() throws -> URL {
        guard let url = URL(string: serverAddress),
              let scheme = url.scheme,
              ["http", "https"].contains(scheme),
              url.host != nil else {
            throw AppError.invalidServerURL
        }
        return url
    }

    private func preferredModel(from models: [OllamaModel]) -> String? {
        let preferences = ["qwen", "gemma", "llama"]
        for prefix in preferences {
            if let model = models.first(where: { $0.name.lowercased().contains(prefix) }) {
                return model.name
            }
        }
        return models.first?.name
    }

    private func friendlyConnectionError(_ error: Error) -> String {
        if let urlError = error as? URLError,
           [.cannotConnectToHost, .networkConnectionLost, .timedOut].contains(urlError.code) {
            return "连接不到 Ollama。请先打开 Ollama 应用，确认服务地址为 \(serverAddress)。"
        }
        return error.localizedDescription
    }

    private func inferredEmotion(from text: String) -> AvatarState {
        if text.contains("开心") || text.contains("太好了") || text.contains("哈哈") {
            return .happy
        }
        if text.contains("担心") || text.contains("难过") || text.contains("抱抱") {
            return .concerned
        }
        return .idle
    }

    private func scheduleIdleState() {
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.2))
            guard let self, !speechOutput.isSpeaking, !speechInput.isListening else { return }
            avatarState = .idle
        }
    }
}
