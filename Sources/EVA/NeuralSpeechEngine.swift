import Foundation
import MLX

struct NeuralSpeechAudio: Sendable {
    let samples: [Float]
    let sampleRate: Int
}

enum NeuralSpeechError: LocalizedError {
    case modelMissing(URL)
    case engineCreationFailed
    case generationFailed

    var errorDescription: String? {
        switch self {
        case .modelMissing(let url):
            "未找到 EVA 神经语音模型：\(url.path)"
        case .engineCreationFailed:
            "EVA 神经语音引擎初始化失败。"
        case .generationFailed:
            "EVA 神经语音生成失败。"
        }
    }
}

actor QwenSpeechEngine {
    private var model: Qwen3TTSModel?
    private var preparation: Task<Qwen3TTSModel, Error>?

    func prepare() async throws {
        guard model == nil else { return }
        if preparation == nil {
            let directory = try ModelStorage.speechModelURL()
            preparation = Task { try await Qwen3TTSModel.fromPretrained(directory.path) }
        }
        do {
            model = try await preparation?.value
            preparation = nil
        } catch {
            preparation = nil
            throw error
        }
    }

    func synthesize(
        text: String,
        speaker: String,
        instruction: String? = nil
    ) async throws -> NeuralSpeechAudio {
        try Task.checkCancellation()
        try await prepare()
        try Task.checkCancellation()
        guard let model else {
            throw NeuralSpeechError.engineCreationFailed
        }

        // Companion dialogue should be stable and understated.  The upstream
        // defaults are useful for expressive demos, but their wider sampling can
        // make a short conversational reply sound as if it is being performed.
        let attempts: [(temperature: Float, topK: Int, topP: Float)] = [
            (0.82, 40, 0.95),
            (0.74, 32, 0.92)
        ]
        for attempt in attempts {
            // Synchronous generation stays on this actor's executor: a stopped
            // request must unwind before another request can use the same model.
            let generated = try model.generateCustomVoice(
                text: text,
                speaker: speaker,
                language: "chinese",
                instruct: instruction,
                temperature: attempt.temperature,
                topK: attempt.topK,
                topP: attempt.topP,
                repetitionPenalty: 1.05,
                maxTokens: 2_048,
                cancellationCheck: { try Task.checkCancellation() }
            )
            let safeSamples = generated.asArray(Float.self).map {
                $0.isFinite ? min(max($0, -1), 1) : 0
            }
            try Task.checkCancellation()
            if Self.isUsable(samples: safeSamples, sampleRate: model.sampleRate, text: text) {
                Memory.clearCache()
                return NeuralSpeechAudio(samples: safeSamples, sampleRate: model.sampleRate)
            }
            Memory.clearCache()
        }
        throw NeuralSpeechError.generationFailed
    }

    func release() {
        model = nil
        preparation?.cancel()
        preparation = nil
        Memory.clearCache()
    }

    private static func isUsable(
        samples: [Float],
        sampleRate: Int,
        text: String
    ) -> Bool {
        // Chinese companion speech normally needs substantially more than 70 ms per
        // character. This gate catches early-EOS/gibberish generations such as the
        // retired pruned-vocabulary model without making short acknowledgements fail.
        let minimumSeconds = min(max(Double(text.count) * 0.11, 0.9), 4.0)
        let duration = Double(samples.count) / Double(sampleRate)
        guard duration >= minimumSeconds else {
            return false
        }
        let peak = samples.lazy.map(abs).max() ?? 0
        guard peak > 0.002 else { return false }
        let meanSquare = samples.reduce(0.0) { partial, sample in
            partial + Double(sample * sample)
        } / Double(samples.count)
        return sqrt(meanSquare) > 0.000_5
    }
}

enum WaveEncoder {
    static func pcm16Data(from audio: NeuralSpeechAudio) -> Data {
        var pcm = Data(capacity: audio.samples.count * 2)
        for sample in audio.samples {
            let clamped = sample.isFinite ? min(max(sample, -1), 1) : 0
            var value = Int16(clamped * Float(Int16.max)).littleEndian
            Swift.withUnsafeBytes(of: &value) { pcm.append(contentsOf: $0) }
        }

        var result = Data()
        result.appendASCII("RIFF")
        result.appendLittleEndian(UInt32(36 + pcm.count))
        result.appendASCII("WAVE")
        result.appendASCII("fmt ")
        result.appendLittleEndian(UInt32(16))
        result.appendLittleEndian(UInt16(1))
        result.appendLittleEndian(UInt16(1))
        result.appendLittleEndian(UInt32(audio.sampleRate))
        result.appendLittleEndian(UInt32(audio.sampleRate * 2))
        result.appendLittleEndian(UInt16(2))
        result.appendLittleEndian(UInt16(16))
        result.appendASCII("data")
        result.appendLittleEndian(UInt32(pcm.count))
        result.append(pcm)
        return result
    }
}

private extension Data {
    mutating func appendASCII(_ value: String) {
        append(value.data(using: .ascii) ?? Data())
    }

    mutating func appendLittleEndian<T: FixedWidthInteger>(_ value: T) {
        var littleEndian = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndian) { append(contentsOf: $0) }
    }
}
