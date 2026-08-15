import XCTest
@testable import EVA

final class NeuralSpeechEngineTests: XCTestCase {
    func testQwenTTSGeneratesAudibleChineseWaveform() async throws {
        let engine = QwenSpeechEngine()
        let audio = try await engine.synthesize(
            text: "你好，我会一直在这里陪着你。",
            speaker: "Serena"
        )

        XCTAssertGreaterThan(audio.sampleRate, 8_000)
        let duration = Double(audio.samples.count) / Double(audio.sampleRate)
        XCTAssertGreaterThan(duration, 2.0, "中文语音异常短，可能提前结束或未正确发音")
        XCTAssertLessThan(duration, 10.0, "中文语音异常长，可能出现重复生成")
        XCTAssertTrue(audio.samples.contains { abs($0) > 0.001 })

        let wave = WaveEncoder.pcm16Data(from: audio)
        XCTAssertEqual(String(data: wave.prefix(4), encoding: .ascii), "RIFF")
        XCTAssertGreaterThan(wave.count, 44)
    }

    func testQwenTTSHandlesCompanionNameInPreviewSentence() async throws {
        let engine = QwenSpeechEngine()
        let audio = try await engine.synthesize(
            text: "晚上好，我是 EVA。很高兴见到你，今天想和我聊些什么？",
            speaker: "Vivian"
        )

        let duration = Double(audio.samples.count) / Double(audio.sampleRate)
        XCTAssertGreaterThan(duration, 3.0, "预览语音异常短，不能仅以存在波形判定通过")
        XCTAssertLessThan(duration, 14.0, "预览语音异常长，可能出现重复生成")
        XCTAssertTrue(audio.samples.contains { abs($0) > 0.001 })
    }

    func testWaveEncoderSafelySilencesNonFiniteSamples() {
        let audio = NeuralSpeechAudio(
            samples: [.nan, .infinity, -.infinity, 0.25],
            sampleRate: 24_000
        )

        XCTAssertEqual(WaveEncoder.pcm16Data(from: audio).count, 52)
    }
}
