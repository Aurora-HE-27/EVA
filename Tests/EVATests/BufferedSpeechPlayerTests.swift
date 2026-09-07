import Foundation
import XCTest
@testable import EVA

/// Uses the real output render clock, but mutes the node before it starts.
/// No microphone, neural model, or audible test sound is involved.
@MainActor
final class BufferedSpeechPlayerTests: XCTestCase {
    private struct StartedSegment {
        let requestID: UUID
        let index: Int
        let text: String
        let time: TimeInterval
    }

    func testQueuedSegmentsStartOnTheirOwnAudioTimelineAndFinishAfterDrain() async throws {
        let player = BufferedSpeechPlayer(volume: 0)
        defer { player.stop() }
        let requestID = UUID()
        let audio = Self.testAudio()
        var starts: [StartedSegment] = []
        var finishes: [(UUID, TimeInterval)] = []
        var playingStates: [Bool] = []
        player.onSegmentStarted = { id, index, text in
            starts.append(StartedSegment(requestID: id, index: index, text: text, time: Self.now))
        }
        player.onFinished = { id in finishes.append((id, Self.now)) }
        player.onPlayingChanged = { playingStates.append($0) }

        player.begin(requestID)
        let beganAt = Self.now
        try player.append(audio, index: 0, text: "第一段。", requestID: requestID)
        try player.append(audio, index: 1, text: "第二段。", requestID: requestID)
        player.finishScheduling(requestID: requestID)

        XCTAssertTrue(starts.isEmpty, "排队不能冒充真正开口。")
        XCTAssertTrue(finishes.isEmpty, "完成排队不等于扬声器播放结束。")
        guard try await waitUntil("两段静音渲染应完整播放结束", condition: { !finishes.isEmpty }) else { return }

        XCTAssertEqual(starts.map(\.requestID), [requestID, requestID])
        XCTAssertEqual(starts.map(\.index), [0, 1])
        XCTAssertEqual(starts.map(\.text), ["第一段。", "第二段。"])
        let firstStart = try XCTUnwrap(starts.first)
        let secondStart = try XCTUnwrap(starts.last)
        // Each fixture has 100 ms of leading silence and lasts 350 ms.
        // Small lower-bound tolerances allow device render-block granularity;
        // there is no tight upper bound that would fail on a busy machine.
        XCTAssertGreaterThanOrEqual(firstStart.time - beganAt, 0.075)
        XCTAssertGreaterThanOrEqual(secondStart.time - beganAt, 0.410)
        XCTAssertEqual(finishes.count, 1)
        XCTAssertEqual(finishes.first?.0, requestID)
        let finishedAt = try XCTUnwrap(finishes.first?.1)
        XCTAssertGreaterThanOrEqual(finishedAt - beganAt, 0.660)
        XCTAssertGreaterThanOrEqual(finishedAt, secondStart.time)
        XCTAssertTrue(playingStates.contains(true))
        XCTAssertEqual(playingStates.last, false)
    }

    func testStopAndSameExternalIDReuseCannotAcceptOldCompletionCallbacks() async throws {
        let player = BufferedSpeechPlayer(volume: 0)
        defer { player.stop() }
        let reusedID = UUID()
        let audio = Self.testAudio()
        var starts: [StartedSegment] = []
        var finishes: [(UUID, TimeInterval)] = []
        player.onSegmentStarted = { id, index, text in
            starts.append(StartedSegment(requestID: id, index: index, text: text, time: Self.now))
        }
        player.onFinished = { id in finishes.append((id, Self.now)) }

        player.begin(reusedID)
        try player.append(audio, index: 90, text: "已停止的旧段一。", requestID: reusedID)
        try player.append(audio, index: 91, text: "已停止的旧段二。", requestID: reusedID)
        player.finishScheduling(requestID: reusedID)
        // Do not yield the main actor between stop and reuse: callbacks caused
        // by stopping the old node will have to validate against the new run.
        player.stop()
        player.begin(reusedID)
        let restartedAt = Self.now
        try player.append(audio, index: 0, text: "这是新的播放。", requestID: reusedID)
        player.finishScheduling(requestID: reusedID)

        XCTAssertTrue(finishes.isEmpty)
        guard try await waitUntil("同一外部 ID 的新播放应独立结束", condition: { !finishes.isEmpty }) else { return }
        // Give already-enqueued completion tasks a chance to expose a duplicate.
        try await Task.sleep(for: .milliseconds(80))

        XCTAssertEqual(starts.map(\.index), [0])
        XCTAssertEqual(starts.map(\.text), ["这是新的播放。"])
        XCTAssertEqual(starts.first?.requestID, reusedID)
        let startedAt = try XCTUnwrap(starts.first?.time)
        XCTAssertGreaterThanOrEqual(startedAt - restartedAt, 0.075)
        XCTAssertEqual(finishes.count, 1, "旧完成回调不能增加新一轮的完成次数。")
        XCTAssertEqual(finishes.first?.0, reusedID)
        let finishedAt = try XCTUnwrap(finishes.first?.1)
        XCTAssertGreaterThanOrEqual(finishedAt - restartedAt, 0.310,
                                    "旧回调不能让新缓冲区未播完就宣布结束。")
    }

    func testLateSecondSegmentWaitsForItsNewAudibleTime() async throws {
        let player = BufferedSpeechPlayer(volume: 0)
        defer { player.stop() }
        let requestID = UUID()
        let audio = Self.testAudio()
        var starts: [StartedSegment] = []
        var finishes: [(UUID, TimeInterval)] = []
        var hasPlayed = false
        var firstSegmentDrained = false
        player.onSegmentStarted = { id, index, text in
            starts.append(StartedSegment(requestID: id, index: index, text: text, time: Self.now))
        }
        player.onPlayingChanged = { playing in
            if playing {
                hasPlayed = true
            } else if hasPlayed {
                firstSegmentDrained = true
            }
        }
        player.onFinished = { id in finishes.append((id, Self.now)) }

        player.begin(requestID)
        try player.append(audio, index: 0, text: "先播放这一段。", requestID: requestID)
        // Deliberately leave scheduling open while the first buffer drains.
        guard try await waitUntil("第一段应先播完并进入等待", condition: { firstSegmentDrained }) else { return }
        XCTAssertEqual(starts.map(\.index), [0])
        XCTAssertTrue(finishes.isEmpty, "等待后续片段时不能结束整轮播放。")
        // Make this an unambiguously late producer, beyond the first buffer and
        // device render block rather than racing its exact final sample.
        try await Task.sleep(for: .milliseconds(100))
        let appendedAt = Self.now
        try player.append(audio, index: 1, text: "后来才准备好的第二段。", requestID: requestID)
        player.finishScheduling(requestID: requestID)

        XCTAssertEqual(starts.map(\.index), [0], "迟到音频不能按旧缓冲区结束时间提前公告。")
        XCTAssertTrue(finishes.isEmpty)
        guard try await waitUntil("迟到的第二段也应真正播放结束", condition: { !finishes.isEmpty }) else { return }

        XCTAssertEqual(starts.map(\.index), [0, 1])
        let secondStart = try XCTUnwrap(starts.last)
        XCTAssertEqual(secondStart.text, "后来才准备好的第二段。")
        // The new lead plus fixture preroll is nominally 150 ms. Permit one
        // or two render blocks, while still rejecting an immediate announcement.
        XCTAssertGreaterThanOrEqual(secondStart.time - appendedAt, 0.110)
        XCTAssertEqual(finishes.count, 1)
        let finishedAt = try XCTUnwrap(finishes.first?.1)
        XCTAssertGreaterThanOrEqual(finishedAt - appendedAt, 0.340)
        XCTAssertGreaterThanOrEqual(finishedAt, secondStart.time)
    }

    private static var now: TimeInterval { ProcessInfo.processInfo.systemUptime }

    private static func testAudio() -> NeuralSpeechAudio {
        let sampleRate = 24_000
        let silentFrames = sampleRate / 10
        let toneFrames = sampleRate / 4
        let samples = [Float](repeating: 0, count: silentFrames) + (0..<toneFrames).map { frame in
            Float(sin(2 * Double.pi * 440 * Double(frame) / Double(sampleRate))) * 0.01
        }
        return NeuralSpeechAudio(samples: samples, sampleRate: sampleRate)
    }

    private func waitUntil(
        _ description: String,
        timeout: TimeInterval = 5,
        file: StaticString = #filePath,
        line: UInt = #line,
        condition: () -> Bool
    ) async throws -> Bool {
        let deadline = Self.now + timeout
        while !condition() {
            if Self.now >= deadline {
                XCTFail(description, file: file, line: line)
                return false
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        return true
    }
}
