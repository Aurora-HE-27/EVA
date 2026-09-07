import AVFoundation
import Foundation

@MainActor
final class SpeechOutputService: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    @Published private(set) var isSpeaking = false
    @Published private(set) var isBusy = false

    var onSpeakingChanged: ((Bool) -> Void)?
    var onSegmentStarted: ((UUID, Int, String) -> Void)?
    var onFinished: ((UUID) -> Void)?
    var onFailure: ((UUID, String) -> Void)?

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

    private struct SystemItem {
        let requestID: UUID
        let index: Int
        let text: String
    }

    private let synthesizer = AVSpeechSynthesizer()
    private let neuralEngine = QwenSpeechEngine()
    private let player = BufferedSpeechPlayer()
    private var neuralTask: Task<Void, Never>?
    private var stoppedSynthesis: Task<Void, Never>?
    private var activeRequestID: UUID?
    private var activeSystemUtterances: [ObjectIdentifier: SystemItem] = [:]

    override init() {
        super.init()
        synthesizer.delegate = self
        player.onSegmentStarted = { [weak self] id, index, text in
            guard let self, self.activeRequestID == id else { return }
            self.onSegmentStarted?(id, index, text)
        }
        player.onPlayingChanged = { [weak self] value in self?.setSpeaking(value) }
        player.onFinished = { [weak self] id in self?.finish(id) }
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

    func prepareNeuralVoice() async throws {
        try await neuralEngine.prepare()
    }

    func enqueue(
        _ text: String,
        requestID: UUID = UUID(),
        voiceIdentifier: String?,
        rate: Double = 0.48,
        pitch: Double = 1.02,
        emotion: EmotionDirective = .neutral
    ) {
        enqueue(
            segments: Self.spokenSegments(for: text),
            requestID: requestID,
            voiceIdentifier: voiceIdentifier,
            rate: rate,
            pitch: pitch,
            emotion: emotion
        )
    }

    static func spokenSegments(for text: String) -> [String] {
        SpokenReplySegmenter.segments(for: SpokenTextNormalizer.normalize(text))
    }

    /// Accepts the same immutable plan used by the transcript. Never normalize
    /// again here: a second cleanup pass could change what the subtitles say.
    func enqueue(
        segments: [String],
        requestID: UUID,
        voiceIdentifier: String?,
        rate: Double = 0.48,
        pitch: Double = 1.02,
        emotion: EmotionDirective = .neutral
    ) {
        stop()
        activeRequestID = requestID
        isBusy = true
        guard !segments.isEmpty, segments.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
            fail(requestID, description: "这条回复没有可以播放的内容。")
            return
        }

        if Self.isNeuralVoiceIdentifier(voiceIdentifier) {
            player.begin(requestID)
            neuralTask = Task { [weak self] in
                guard let self else { return }
                do {
                    for (index, segment) in segments.enumerated() {
                        try Task.checkCancellation()
                        guard activeRequestID == requestID else { throw CancellationError() }
                        let audio = try await neuralEngine.synthesize(
                            text: segment,
                            speaker: Self.speakerName(for: voiceIdentifier ?? Self.neuralFeminineVoiceIdentifier),
                            instruction: nil
                        )
                        try Task.checkCancellation()
                        guard activeRequestID == requestID else { throw CancellationError() }
                        try player.append(audio, index: index, text: segment, requestID: requestID)
                        // The next synthesis runs while the audio node plays this
                        // segment. One actor serializes model access across stops.
                    }
                    guard activeRequestID == requestID else { return }
                    neuralTask = nil
                    player.finishScheduling(requestID: requestID)
                } catch is CancellationError {
                    // stop() owns cleanup; an old task must not clear a new reply.
                } catch {
                    guard activeRequestID == requestID else { return }
                    fail(requestID, description: "本地神经语音暂时无法播放，请重试。没有切换成系统朗读声。\n\(error.localizedDescription)")
                }
            }
            return
        }

        let adjustment = Self.voiceAdjustment(for: emotion)
        let resolvedIdentifier = voiceIdentifier == Self.retiredMLXVoiceIdentifier
            ? Self.systemFallbackVoiceIdentifier
            : voiceIdentifier
        let systemVoice = resolvedIdentifier.flatMap(AVSpeechSynthesisVoice.init(identifier:))
            ?? AVSpeechSynthesisVoice(identifier: Self.systemFallbackVoiceIdentifier)
            ?? AVSpeechSynthesisVoice(language: "zh-CN")
        guard let systemVoice else {
            fail(requestID, description: "EVA 暂时无法发声，请检查声音设置后重试。")
            return
        }
        for (index, segment) in segments.enumerated() {
            let utterance = AVSpeechUtterance(string: segment)
            utterance.voice = systemVoice
            utterance.rate = Float(min(max(rate * adjustment.rate, 0.35), 0.62))
            utterance.pitchMultiplier = Float(min(max(pitch * adjustment.pitch, 0.92), 1.08))
            utterance.volume = Float(adjustment.volume)
            activeSystemUtterances[ObjectIdentifier(utterance)] = SystemItem(requestID: requestID, index: index, text: segment)
            synthesizer.speak(utterance)
        }
    }

    func stop() {
        activeRequestID = nil
        if let neuralTask {
            let previous = stoppedSynthesis
            // Rapid stop / replay / stop can cancel a new task before it ever
            // enters the model actor. Do not lose the older in-flight GPU work.
            stoppedSynthesis = Task {
                await previous?.value
                await neuralTask.value
            }
        }
        neuralTask?.cancel()
        neuralTask = nil
        player.stop()
        activeSystemUtterances.removeAll()
        synthesizer.stopSpeaking(at: .immediate)
        isBusy = false
        setSpeaking(false)
    }

    func shutdown() {
        stop()
        Task { await neuralEngine.release() }
    }

    func waitForStoppedSynthesis() async {
        await stoppedSynthesis?.value
    }

    private func finish(_ id: UUID) {
        guard activeRequestID == id else { return }
        activeRequestID = nil
        neuralTask = nil
        isBusy = false
        setSpeaking(false)
        // Keep weights resident. Clearing the model here made every turn cold.
        onFinished?(id)
    }

    private func fail(_ id: UUID, description: String) {
        guard activeRequestID == id else { return }
        stop()
        onFailure?(id, description)
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
        Task { @MainActor in
            guard let item = activeSystemUtterances[ObjectIdentifier(utterance)],
                  activeRequestID == item.requestID else { return }
            onSegmentStarted?(item.requestID, item.index, item.text)
            setSpeaking(true)
        }
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didFinish utterance: AVSpeechUtterance
    ) {
        Task { @MainActor in
            guard let item = activeSystemUtterances.removeValue(forKey: ObjectIdentifier(utterance)),
                  activeRequestID == item.requestID else { return }
            if activeSystemUtterances.isEmpty { finish(item.requestID) }
        }
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didCancel utterance: AVSpeechUtterance
    ) {
        Task { @MainActor in
            guard let item = activeSystemUtterances.removeValue(forKey: ObjectIdentifier(utterance)),
                  activeRequestID == item.requestID else { return }
            fail(item.requestID, description: "语音播放中断，请再试一次。")
        }
    }

    private func setSpeaking(_ value: Bool) {
        guard isSpeaking != value else { return }
        isSpeaking = value
        onSpeakingChanged?(value)
    }
}
