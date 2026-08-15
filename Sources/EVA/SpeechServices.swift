import AVFoundation
import Foundation
import Speech

@MainActor
final class SpeechOutputService: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    @Published private(set) var isSpeaking = false

    var onSpeakingChanged: ((Bool) -> Void)?

    static let retiredMLXVoiceIdentifier = "eva.qwen3.voice-design"
    static let retiredKokoroVoiceIdentifiers: Set<String> = [
        "eva.kokoro.zf_001",
        "eva.kokoro.zm_009",
        "eva.kokoro.zf_032"
    ]
    static let neuralFeminineVoiceIdentifier = "eva.qwen3tts.serena"
    static let neuralBrightVoiceIdentifier = "eva.qwen3tts.vivian"
    static let neuralMasculineVoiceIdentifier = "eva.qwen3tts.dylan"
    static let neuralNeutralVoiceIdentifier = neuralBrightVoiceIdentifier

    static let neuralVoiceOptions: [(identifier: String, label: String)] = [
        (neuralFeminineVoiceIdentifier, "Serena · 温柔年轻女声"),
        (neuralBrightVoiceIdentifier, "Vivian · 明亮年轻女声"),
        (neuralMasculineVoiceIdentifier, "Dylan · 年轻男声")
    ]

    private struct SpeechItem {
        let text: String
        let voiceIdentifier: String
        let rate: Double
        let emotion: EmotionDirective
    }

    private let synthesizer = AVSpeechSynthesizer()
    private let neuralEngine = QwenSpeechEngine()
    private var neuralQueue: [SpeechItem] = []
    private var neuralTask: Task<Void, Never>?
    private var audioPlayer: AVAudioPlayer?

    override init() {
        super.init()
        synthesizer.delegate = self
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

    static func neuralVoiceIdentifier(for gender: CompanionGender) -> String {
        switch gender {
        case .feminine: neuralFeminineVoiceIdentifier
        case .masculine: neuralMasculineVoiceIdentifier
        case .neutral: neuralNeutralVoiceIdentifier
        }
    }

    static func isNeuralVoiceIdentifier(_ identifier: String?) -> Bool {
        guard let identifier else { return false }
        return neuralVoiceOptions.contains { $0.identifier == identifier }
    }

    func prepareNeuralVoice() {
        _ = try? ModelStorage.speechModelURL()
    }

    func enqueue(
        _ text: String,
        voiceIdentifier: String?,
        rate: Double = 0.48,
        pitch: Double = 1.02,
        emotion: EmotionDirective = .neutral
    ) {
        let cleanText = SpokenTextNormalizer.normalize(text)
        guard !cleanText.isEmpty else { return }

        if Self.isNeuralVoiceIdentifier(voiceIdentifier) {
            neuralQueue.append(
                SpeechItem(
                    text: cleanText,
                    voiceIdentifier: voiceIdentifier ?? Self.neuralFeminineVoiceIdentifier,
                    rate: rate,
                    emotion: emotion
                )
            )
            beginNeuralProcessingIfNeeded()
            return
        }

        let adjustment = Self.voiceAdjustment(for: emotion)
        let utterance = AVSpeechUtterance(string: cleanText)
        let resolvedIdentifier = voiceIdentifier == Self.retiredMLXVoiceIdentifier
            ? Self.systemFallbackVoiceIdentifier
            : voiceIdentifier
        utterance.voice = resolvedIdentifier.flatMap(AVSpeechSynthesisVoice.init(identifier:))
            ?? AVSpeechSynthesisVoice(identifier: Self.systemFallbackVoiceIdentifier)
            ?? AVSpeechSynthesisVoice(language: "zh-CN")
        utterance.rate = Float(min(max(rate * adjustment.rate, 0.35), 0.62))
        utterance.pitchMultiplier = Float(min(max(pitch * adjustment.pitch, 0.92), 1.08))
        utterance.volume = Float(adjustment.volume)
        utterance.preUtteranceDelay = adjustment.preDelay
        utterance.postUtteranceDelay = adjustment.postDelay
        synthesizer.speak(utterance)
    }

    func stop() {
        neuralTask?.cancel()
        neuralTask = nil
        neuralQueue.removeAll()
        audioPlayer?.stop()
        audioPlayer = nil
        synthesizer.stopSpeaking(at: .immediate)
        setSpeaking(false)
    }

    func shutdown() {
        stop()
    }

    private func beginNeuralProcessingIfNeeded() {
        guard neuralTask == nil else { return }
        neuralTask = Task { [weak self] in
            await self?.processNeuralQueue()
        }
    }

    private func processNeuralQueue() async {
        setSpeaking(true)
        defer {
            neuralTask = nil
            audioPlayer = nil
            if !synthesizer.isSpeaking {
                setSpeaking(false)
            }
        }

        while !neuralQueue.isEmpty, !Task.isCancelled {
            let item = neuralQueue.removeFirst()
            do {
                let audio = try await neuralEngine.synthesize(
                    text: item.text,
                    speaker: Self.speakerName(for: item.voiceIdentifier),
                    // Let the speaker model infer understated prosody from the
                    // sentence itself. Repeating an emotion/style direction on
                    // every turn produces the uncanny "performed" delivery that
                    // is especially noticeable in intimate conversation.
                    instruction: nil
                )
                guard !Task.isCancelled else { break }
                let player = try AVAudioPlayer(data: WaveEncoder.pcm16Data(from: audio))
                audioPlayer = player
                player.prepareToPlay()
                player.play()
                while player.isPlaying, !Task.isCancelled {
                    try await Task.sleep(for: .milliseconds(40))
                }
            } catch is CancellationError {
                break
            } catch {
                speakWithSystemFallback(item)
            }
        }
        await neuralEngine.release()
    }

    private func speakWithSystemFallback(_ item: SpeechItem) {
        let adjustment = Self.voiceAdjustment(for: item.emotion)
        let utterance = AVSpeechUtterance(string: item.text)
        utterance.voice = AVSpeechSynthesisVoice(identifier: Self.systemFallbackVoiceIdentifier)
            ?? AVSpeechSynthesisVoice(language: "zh-CN")
        utterance.rate = Float(min(max(item.rate * adjustment.rate, 0.35), 0.58))
        utterance.pitchMultiplier = Float(adjustment.pitch)
        utterance.volume = Float(adjustment.volume)
        utterance.preUtteranceDelay = adjustment.preDelay
        utterance.postUtteranceDelay = adjustment.postDelay
        synthesizer.speak(utterance)
    }

    private static func speakerName(for identifier: String) -> String {
        switch identifier {
        case neuralBrightVoiceIdentifier: "Vivian"
        case neuralMasculineVoiceIdentifier: "Dylan"
        default: "Serena"
        }
    }

    private static func voiceAdjustment(
        for emotion: EmotionDirective
    ) -> (rate: Double, pitch: Double, volume: Double, preDelay: TimeInterval, postDelay: TimeInterval) {
        let base: (rate: Double, pitch: Double, volume: Double, preDelay: TimeInterval, postDelay: TimeInterval) =
            switch emotion.emotion {
            case .neutral: (1, 1, 1, 0.02, 0.07)
            case .warm: (0.94, 1.005, 0.96, 0.05, 0.12)
            case .happy: (1.05, 1.02, 1, 0.01, 0.06)
            case .concerned: (0.89, 0.99, 0.93, 0.08, 0.16)
            case .sad: (0.84, 0.98, 0.90, 0.10, 0.20)
            case .surprised: (1.07, 1.025, 1, 0.01, 0.05)
            case .focused: (0.97, 0.995, 0.98, 0.03, 0.08)
            }
        let arousalRate = 0.94 + emotion.arousal * 0.12
        let valencePitch = 1 + emotion.valence * 0.025
        return (
            base.rate * arousalRate,
            base.pitch * valencePitch,
            base.volume,
            base.preDelay,
            base.postDelay
        )
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didStart utterance: AVSpeechUtterance
    ) {
        Task { @MainActor in setSpeaking(true) }
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
        Task { @MainActor in setSpeaking(false) }
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
