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

    func testQwenTTSCancelsInFlightGenerationAndReusesEngine() async throws {
        let engine = QwenSpeechEngine()
        // Load first: cancellation must exercise the token loop, not just abort
        // an awaiting model download/load before generation starts.
        try await engine.prepare()
        let finished = expectation(description: "Cancelled synthesis has unwound")
        let outcome = CancellationOutcomeBox()
        let synthesis = Task {
            do {
                _ = try await engine.synthesize(
                    text: "我想跟你聊聊今天发生的事情。早上出门的时候，路边的花开了，风吹过来很舒服。后来我在小店里遇到一只猫，它趴在窗台上，一点也不怕人。说到这里，你今天有没有遇见什么让自己开心的小事？",
                    speaker: "Serena"
                )
                outcome.store(.returnedAudio)
            } catch is CancellationError {
                outcome.store(.cancelled)
            } catch {
                outcome.store(.failed(String(describing: error)))
            }
            finished.fulfill()
        }
        defer { synthesis.cancel() }

        try await Task.sleep(for: .milliseconds(80))
        let cancelStarted = ProcessInfo.processInfo.systemUptime
        synthesis.cancel()
        // An unstructured task + expectation bounds the wait. A task-group
        // timeout would still await a stuck synchronous GPU child on scope exit.
        await fulfillment(of: [finished], timeout: 8.0)
        guard let result = outcome.load() else {
            XCTFail("语音生成取消后未在 8 秒内结束；不排入同引擎的后续推理")
            return
        }
        switch result {
        case .cancelled:
            break
        case .returnedAudio:
            XCTFail("已取消的语音生成仍返回了音频")
            await engine.release()
            return
        case .failed(let message):
            XCTFail("取消应抛出 CancellationError，实际错误：\(message)")
            await engine.release()
            return
        }
        let cancelSeconds = ProcessInfo.processInfo.systemUptime - cancelStarted

        // Use precisely the same loaded model after the previous call unwinds.
        let recovered = try await engine.synthesize(
            text: "没关系，我们接着聊吧。",
            speaker: "Serena"
        )
        XCTAssertGreaterThan(recovered.sampleRate, 8_000)
        XCTAssertGreaterThan(recovered.samples.count, recovered.sampleRate)
        XCTAssertTrue(recovered.samples.allSatisfy(\.isFinite))
        XCTAssertTrue(recovered.samples.contains { abs($0) > 0.001 })
        print(String(format: "[EVA TTS] cancel_to_exit=%.3fs, same-engine recovery valid", cancelSeconds))
        await engine.release()
    }

    func testQwenTTSReportsColdAndWarmTurnsOnSameEngine() async throws {
        let engine = QwenSpeechEngine()
        for (label, text) in [
            ("cold", "晚上好，今天过得怎么样？"),
            ("warm", "听起来不错，我们慢慢聊。")
        ] {
            let started = ProcessInfo.processInfo.systemUptime
            let audio = try await engine.synthesize(text: text, speaker: "Serena")
            let elapsed = ProcessInfo.processInfo.systemUptime - started
            let duration = Double(audio.samples.count) / Double(audio.sampleRate)
            XCTAssertGreaterThan(audio.sampleRate, 8_000)
            XCTAssertGreaterThan(duration, 1.0)
            XCTAssertTrue(audio.samples.allSatisfy(\.isFinite))
            XCTAssertTrue(audio.samples.contains { abs($0) > 0.001 })
            // Timing is diagnostic: shared machines and GPU warmup vary.
            print(String(format: "[EVA TTS] %@ turn: synthesize=%.3fs, audio=%.3fs", label, elapsed, duration))
        }
        await engine.release()
    }

    func testWaveEncoderSafelySilencesNonFiniteSamples() {
        let audio = NeuralSpeechAudio(
            samples: [.nan, .infinity, -.infinity, 0.25],
            sampleRate: 24_000
        )

        XCTAssertEqual(WaveEncoder.pcm16Data(from: audio).count, 52)
    }
}

/// The synthesis task can finish after the XCTest timeout, so it must not mutate
/// an unprotected test-local variable or capture the XCTestCase itself.
private final class CancellationOutcomeBox: @unchecked Sendable {
    enum Outcome: Sendable {
        case cancelled
        case returnedAudio
        case failed(String)
    }

    private let lock = NSLock()
    private var outcome: Outcome?

    func store(_ value: Outcome) {
        lock.lock()
        defer { lock.unlock() }
        outcome = value
    }

    func load() -> Outcome? {
        lock.lock()
        defer { lock.unlock() }
        return outcome
    }
}
