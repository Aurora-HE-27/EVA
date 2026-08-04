import AVFoundation
import Foundation
import Speech

@MainActor
final class SpeechOutputService: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    @Published private(set) var isSpeaking = false

    var onSpeakingChanged: ((Bool) -> Void)?

    static let evaVoiceIdentifier = "eva.qwen3.voice-design"

    private struct SpeechItem {
        let text: String
        let rate: Double
        let pitch: Double
        let emotion: EmotionDirective
    }

    private struct MLXSpeechRequest: Encodable {
        let model: String
        let input: String
        let instruct: String
        let speed: Double
        let gender: String
        let pitch: Double
        let lang_code: String
        let response_format: String
        let temperature: Double
        let max_tokens: Int
    }

    private let synthesizer = AVSpeechSynthesizer()
    private var mlxQueue: [SpeechItem] = []
    private var mlxTask: Task<Void, Never>?
    private var mlxServerProcess: Process?
    private var mlxLogHandle: FileHandle?
    private var didAttemptMLXServerLaunch = false
    private var audioPlayer: AVAudioPlayer?

    private static let mlxModel = "mlx-community/Qwen3-TTS-12Hz-1.7B-VoiceDesign-bf16"
    private static let mlxServerURL = URL(string: "http://127.0.0.1:11435/v1/audio/speech")!
    static var huggingFaceHomeURL: URL {
        ModelStorage.huggingFaceURL
    }

    private static let evaVoiceDesign = """
    一位二十三岁成年女性的普通话声音，清澈温柔，音色年轻但不幼态，中高音域，轻微自然气声，发音清楚，亲近而有边界感，像在安静房间里与熟悉的朋友交谈；不要模仿任何真人、演员、主播或已有角色。
    """

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    deinit {
        if let mlxServerProcess, mlxServerProcess.isRunning {
            mlxServerProcess.terminate()
        }
        try? mlxLogHandle?.close()
    }

    static var availableVoices: [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix("zh") }
            .sorted {
                if $0.quality != $1.quality {
                    return $0.quality.rawValue > $1.quality.rawValue
                }
                return $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
    }

    static var systemFallbackVoiceIdentifier: String {
        availableVoices.first(where: { $0.name == "Tingting" && $0.language == "zh-CN" })?.identifier
            ?? availableVoices.first(where: { $0.language == "zh-CN" })?.identifier
            ?? ""
    }

    func enqueue(
        _ text: String,
        voiceIdentifier: String?,
        rate: Double = 0.48,
        pitch: Double = 1.02,
        emotion: EmotionDirective = .neutral
    ) {
        let cleanText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanText.isEmpty else { return }

        if voiceIdentifier == Self.evaVoiceIdentifier {
            launchMLXServerIfNeeded()
            mlxQueue.append(
                SpeechItem(
                    text: cleanText,
                    rate: rate,
                    pitch: pitch,
                    emotion: emotion
                )
            )
            beginMLXProcessingIfNeeded()
            return
        }

        speakWithSystem(
            cleanText,
            voiceIdentifier: voiceIdentifier,
            rate: rate,
            pitch: pitch,
            emotion: emotion
        )
    }

    func stop() {
        mlxTask?.cancel()
        mlxTask = nil
        mlxQueue.removeAll()
        audioPlayer?.stop()
        audioPlayer = nil
        synthesizer.stopSpeaking(at: .immediate)
        setSpeaking(false)
    }

    func shutdown() {
        stop()
        if let mlxServerProcess, mlxServerProcess.isRunning {
            mlxServerProcess.terminate()
        }
        mlxServerProcess = nil
        try? mlxLogHandle?.close()
        mlxLogHandle = nil
    }

    private func speakWithSystem(
        _ text: String,
        voiceIdentifier: String?,
        rate: Double,
        pitch: Double,
        emotion: EmotionDirective
    ) {
        let adjustment = Self.systemVoiceAdjustment(for: emotion)
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voiceIdentifier.flatMap(AVSpeechSynthesisVoice.init(identifier:))
            ?? AVSpeechSynthesisVoice(identifier: Self.systemFallbackVoiceIdentifier)
            ?? AVSpeechSynthesisVoice(language: "zh-CN")
        utterance.rate = Float(min(max(rate * adjustment.rate, 0.35), 0.62))
        utterance.pitchMultiplier = Float(min(max(pitch * adjustment.pitch, 0.8), 1.25))
        utterance.preUtteranceDelay = 0.02
        utterance.postUtteranceDelay = 0.04
        synthesizer.speak(utterance)
    }

    private func beginMLXProcessingIfNeeded() {
        guard mlxTask == nil else { return }
        mlxTask = Task { [weak self] in
            await self?.processMLXQueue()
        }
    }

    private func processMLXQueue() async {
        setSpeaking(true)
        defer {
            mlxTask = nil
            audioPlayer = nil
            if !synthesizer.isSpeaking {
                setSpeaking(false)
            }
        }

        while !mlxQueue.isEmpty, !Task.isCancelled {
            let item = mlxQueue.removeFirst()
            do {
                let audioData = try await requestMLXAudio(for: item)
                let player = try AVAudioPlayer(data: audioData)
                audioPlayer = player
                player.prepareToPlay()
                player.play()

                while player.isPlaying, !Task.isCancelled {
                    try await Task.sleep(for: .milliseconds(50))
                }
            } catch is CancellationError {
                return
            } catch {
                speakWithSystem(
                    item.text,
                    voiceIdentifier: Self.systemFallbackVoiceIdentifier,
                    rate: item.rate,
                    pitch: item.pitch,
                    emotion: item.emotion
                )
            }
        }
    }

    private func requestMLXAudio(for item: SpeechItem) async throws -> Data {
        launchMLXServerIfNeeded()

        let relativeSpeed = min(max(item.rate / 0.46, 0.8), 1.2)
        let relativePitch = min(max(item.pitch / 1.06, 0.85), 1.18)
        var request = URLRequest(url: Self.mlxServerURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 180
        request.httpBody = try JSONEncoder().encode(
            MLXSpeechRequest(
                model: Self.mlxModel,
                input: item.text,
                instruct: Self.voiceDesign(for: item.emotion),
                speed: relativeSpeed,
                gender: "female",
                pitch: relativePitch,
                lang_code: "Chinese",
                response_format: "wav",
                temperature: 0.7,
                max_tokens: 768
            )
        )

        var lastError: Error = URLError(.cannotConnectToHost)
        for attempt in 0..<80 {
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse,
                      200..<300 ~= httpResponse.statusCode,
                      !data.isEmpty else {
                    throw URLError(.badServerResponse)
                }
                return data
            } catch {
                lastError = error
                guard attempt < 79 else { break }
                try await Task.sleep(for: .milliseconds(250))
            }
        }
        throw lastError
    }

    private static func voiceDesign(for emotion: EmotionDirective) -> String {
        let emotionInstruction: String
        switch emotion.emotion {
        case .neutral:
            emotionInstruction = "保持自然平静，语气不过度起伏。"
        case .warm:
            emotionInstruction = "此刻温柔亲近，语速略慢，句尾柔和。"
        case .happy:
            emotionInstruction = "带有克制而真实的开心，声音稍明亮，不要夸张。"
        case .concerned:
            emotionInstruction = "带有关心和认真倾听感，语速稍慢，不要表现得悲情。"
        case .sad:
            emotionInstruction = "情绪略低沉但保持稳定与支持感，不要哭腔。"
        case .surprised:
            emotionInstruction = "带有短暂自然的惊喜，随后恢复温和。"
        case .focused:
            emotionInstruction = "语气清楚、专注、可靠，减少气声。"
        }
        let energyDescription: String
        if emotion.arousal < 0.3 {
            energyDescription = "整体能量偏低，留出自然呼吸和短停顿。"
        } else if emotion.arousal > 0.68 {
            energyDescription = "整体能量较高，但保持真实对话感，不要像播音或表演。"
        } else {
            energyDescription = "整体能量适中，节奏自然。"
        }
        let expressionDescription = emotion.intensity < 0.35
            ? "情绪只轻微流露。"
            : emotion.intensity > 0.75
                ? "情绪清晰可感，但避免夸张。"
                : "情绪表达克制而明确。"
        return "\(evaVoiceDesign) \(emotionInstruction) \(energyDescription) \(expressionDescription)"
    }

    private static func systemVoiceAdjustment(
        for emotion: EmotionDirective
    ) -> (rate: Double, pitch: Double) {
        let base: (rate: Double, pitch: Double) = switch emotion.emotion {
        case .neutral: (1, 1)
        case .warm: (0.96, 1.01)
        case .happy: (1.04, 1.04)
        case .concerned: (0.92, 0.98)
        case .sad: (0.89, 0.95)
        case .surprised: (1.06, 1.07)
        case .focused: (0.98, 0.99)
        }
        let arousalRate = 0.94 + emotion.arousal * 0.12
        let valencePitch = 1 + emotion.valence * 0.025
        return (base.rate * arousalRate, base.pitch * valencePitch)
    }

    private func launchMLXServerIfNeeded() {
        guard !didAttemptMLXServerLaunch else { return }
        didAttemptMLXServerLaunch = true

        let executable = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: ".local/bin/mlx_audio.server")
            .resolvingSymlinksInPath()

        let supportDirectory = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0].appending(path: "EVA", directoryHint: .isDirectory)
        let logURL = supportDirectory.appending(path: "mlx-audio.log")

        do {
            try FileManager.default.createDirectory(
                at: supportDirectory,
                withIntermediateDirectories: true
            )
            try ModelStorage.prepareDirectories()
            if !FileManager.default.fileExists(atPath: logURL.path) {
                FileManager.default.createFile(atPath: logURL.path, contents: nil)
            }
            let logHandle = try FileHandle(forWritingTo: logURL)
            try logHandle.seekToEnd()
            mlxLogHandle = logHandle
        } catch {
            mlxLogHandle = nil
        }

        guard FileManager.default.isExecutableFile(atPath: executable.path) else {
            writeMLXLog("MLX-Audio executable is unavailable at \(executable.path)\n")
            return
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [
            executable.path,
            "--host", "127.0.0.1",
            "--port", "11435",
            "--log-dir", supportDirectory.appending(path: "MLXAudioLogs").path
        ]
        process.environment = ProcessInfo.processInfo.environment.merging(
            [
                "HF_HOME": Self.huggingFaceHomeURL.path,
                "PYTHONUNBUFFERED": "1"
            ],
            uniquingKeysWith: { _, newValue in newValue }
        )
        process.standardOutput = mlxLogHandle ?? FileHandle.nullDevice
        process.standardError = mlxLogHandle ?? FileHandle.nullDevice
        do {
            try process.run()
            mlxServerProcess = process
        } catch {
            writeMLXLog("Failed to launch MLX-Audio: \(error.localizedDescription)\n")
            mlxServerProcess = nil
        }
    }

    private func writeMLXLog(_ message: String) {
        guard let data = message.data(using: .utf8) else { return }
        try? mlxLogHandle?.write(contentsOf: data)
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didStart utterance: AVSpeechUtterance
    ) {
        Task { @MainActor in
            setSpeaking(true)
        }
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didFinish utterance: AVSpeechUtterance
    ) {
        Task { @MainActor in
            if !synthesizer.isSpeaking {
                setSpeaking(false)
            }
        }
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didCancel utterance: AVSpeechUtterance
    ) {
        Task { @MainActor in
            setSpeaking(false)
        }
    }

    private func setSpeaking(_ value: Bool) {
        isSpeaking = value
        onSpeakingChanged?(value)
    }
}

@MainActor
final class SpeechInputService: ObservableObject {
    @Published private(set) var isListening = false
    @Published private(set) var transcript = ""
    @Published private(set) var errorMessage: String?

    private let audioEngine = AVAudioEngine()
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh-CN"))
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    func start() async {
        guard !isListening else { return }
        errorMessage = nil

        do {
            guard await requestSpeechAuthorization() else {
                throw SpeechInputError.speechPermissionDenied
            }
            guard await AVCaptureDevice.requestAccess(for: .audio) else {
                throw SpeechInputError.microphonePermissionDenied
            }
            try beginRecognition()
        } catch {
            errorMessage = error.localizedDescription
            stop()
        }
    }

    @discardableResult
    func stop() -> String {
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
        isListening = false
        return transcript.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func clear() {
        transcript = ""
        errorMessage = nil
    }

    private func beginRecognition() throws {
        guard let recognizer, recognizer.isAvailable else {
            throw SpeechInputError.recognizerUnavailable
        }

        transcript = ""
        task?.cancel()
        task = nil

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.addsPunctuation = true
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        } else {
            throw SpeechInputError.onDeviceRecognitionUnavailable
        }
        self.request = request

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1_024, format: format) { [weak request] buffer, _ in
            request?.append(buffer)
        }

        audioEngine.prepare()
        try audioEngine.start()
        isListening = true

        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                guard let self else { return }
                if let result {
                    self.transcript = result.bestTranscription.formattedString
                }
                if let error, self.isListening {
                    self.errorMessage = error.localizedDescription
                    _ = self.stop()
                }
            }
        }
    }

    private func requestSpeechAuthorization() async -> Bool {
        let current = SFSpeechRecognizer.authorizationStatus()
        if current == .authorized {
            return true
        }
        return await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }
}

enum SpeechInputError: LocalizedError {
    case speechPermissionDenied
    case microphonePermissionDenied
    case recognizerUnavailable
    case onDeviceRecognitionUnavailable

    var errorDescription: String? {
        switch self {
        case .speechPermissionDenied:
            "EVA 没有语音识别权限，请在系统设置中允许。"
        case .microphonePermissionDenied:
            "EVA 没有麦克风权限，请在系统设置中允许。"
        case .recognizerUnavailable:
            "当前无法使用中文语音识别。"
        case .onDeviceRecognitionUnavailable:
            "这台 Mac 尚未准备好离线中文语音识别，请先下载中文听写语言资源。"
        }
    }
}
