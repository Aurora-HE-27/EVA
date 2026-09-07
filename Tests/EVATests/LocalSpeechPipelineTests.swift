import XCTest
@testable import EVA

@MainActor
final class LocalSpeechPipelineTests: XCTestCase {
    func testLocalSynthesisPreparesNextSegmentWhileAudioQueuePlays() async throws {
        let engine = QwenSpeechEngine()
        let player = BufferedSpeechPlayer(volume: 0)
        defer { player.stop() }
        try await engine.prepare()
        let id = UUID()
        let segments = [
            "今天先别急着安排什么，我们可以慢慢聊一会儿。",
            "你想说点开心的事情，还是随便聊聊刚才的想法？"
        ]
        let began = ProcessInfo.processInfo.systemUptime
        var starts: [(Int, Double)] = []
        var preparedAt: [Double] = []
        var durations: [Double] = []
        var finished = false
        player.onSegmentStarted = { request, index, text in
            XCTAssertEqual(request, id)
            XCTAssertEqual(text, segments[index])
            starts.append((index, ProcessInfo.processInfo.systemUptime - began))
        }
        player.onFinished = { request in
            XCTAssertEqual(request, id)
            finished = true
        }
        player.begin(id)
        for (index, segment) in segments.enumerated() {
            let audio = try await engine.synthesize(text: segment, speaker: "Serena")
            preparedAt.append(ProcessInfo.processInfo.systemUptime - began)
            durations.append(Double(audio.samples.count) / Double(audio.sampleRate))
            XCTAssertTrue(audio.samples.allSatisfy(\.isFinite))
            XCTAssertTrue(audio.samples.contains { abs($0) > 0.002 })
            try player.append(audio, index: index, text: segment, requestID: id)
            // Intentionally do not wait for playback before generating index 1.
        }
        player.finishScheduling(requestID: id)
        let deadline = ProcessInfo.processInfo.systemUptime + 60
        while !finished, ProcessInfo.processInfo.systemUptime < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertTrue(finished, "真实播放必须排空并返回完成回调")
        XCTAssertEqual(starts.map(\.0), [0, 1])
        if starts.count == 2 {
            XCTAssertGreaterThanOrEqual(starts[0].1, preparedAt[0])
            XCTAssertGreaterThanOrEqual(starts[1].1, preparedAt[1])
            XCTAssertGreaterThan(starts[1].1, starts[0].1)
            let estimatedGap = max(0, preparedAt[1] - (preparedAt[0] + durations[0]))
            print(String(format: "[EVA PIPELINE] first_ready=%.3fs first_audio=%.3fs second_ready=%.3fs second_audio=%.3fs estimated_starvation=%.3fs total=%.3fs",
                         preparedAt[0], starts[0].1, preparedAt[1], starts[1].1, estimatedGap,
                         ProcessInfo.processInfo.systemUptime - began))
        }
        await engine.release()
    }
}
