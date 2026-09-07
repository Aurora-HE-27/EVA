import XCTest
@testable import EVA

final class SpeechPlaybackTimelineTests: XCTestCase {
    private let sampleRate: Int64 = 24_000
    private let schedulingLead: Int64 = 1_200 // 50 ms at 24 kHz.

    func testFirstSegmentStartsAtZeroBeforePlayerClockExists() {
        var timeline = SpeechPlaybackTimeline()
        let segment = timeline.append(
            index: 0, text: "我在听。", frameCount: sampleRate,
            firstAudibleFrame: 0, currentFrame: nil, lateSchedulingLead: schedulingLead
        )

        XCTAssertEqual(segment.startFrame, 0)
        XCTAssertEqual(segment.audibleFrame, 0)
        XCTAssertEqual(segment.endFrame, sampleRate)
        XCTAssertEqual(segment.text, "我在听。")
        XCTAssertTrue(timeline.newlyStarted(at: -1).isEmpty)
        XCTAssertEqual(timeline.newlyStarted(at: 0).map(\.index), [0])
        XCTAssertTrue(timeline.isPlaying(at: 0))
    }

    func testTimelySecondSegmentStartsAtPreviousEndWithoutExtraGap() {
        var timeline = SpeechPlaybackTimeline()
        let first = timeline.append(
            index: 0, text: "第一段。", frameCount: sampleRate,
            firstAudibleFrame: 0, currentFrame: nil, lateSchedulingLead: schedulingLead
        )
        let second = timeline.append(
            index: 1, text: "第二段。", frameCount: sampleRate,
            firstAudibleFrame: 0, currentFrame: sampleRate / 4, lateSchedulingLead: schedulingLead
        )

        XCTAssertEqual(second.startFrame, first.endFrame)
        XCTAssertEqual(second.endFrame, sampleRate * 2)
        XCTAssertEqual(timeline.newlyStarted(at: 0).map(\.index), [0])
        XCTAssertTrue(timeline.newlyStarted(at: first.endFrame - 1).isEmpty)
        XCTAssertTrue(timeline.isPlaying(at: first.endFrame - 1))
        XCTAssertEqual(timeline.newlyStarted(at: first.endFrame).map(\.index), [1])
        XCTAssertTrue(timeline.isPlaying(at: first.endFrame))
    }

    func testSecondSegmentQueuedBeforeClockIsAvailableStillFollowsFirst() {
        var timeline = SpeechPlaybackTimeline()
        _ = timeline.append(
            index: 0, text: "第一段。", frameCount: sampleRate,
            firstAudibleFrame: 0, currentFrame: nil, lateSchedulingLead: schedulingLead
        )
        let second = timeline.append(
            index: 1, text: "第二段。", frameCount: sampleRate,
            firstAudibleFrame: 0, currentFrame: nil, lateSchedulingLead: schedulingLead
        )

        XCTAssertEqual(second.startFrame, sampleRate)
        XCTAssertEqual(second.endFrame, sampleRate * 2)
    }

    func testLateSegmentUsesCurrentClockPlusFiftyMillisecondLead() {
        var timeline = SpeechPlaybackTimeline()
        _ = timeline.append(
            index: 0, text: "第一段。", frameCount: sampleRate,
            firstAudibleFrame: 0, currentFrame: nil, lateSchedulingLead: schedulingLead
        )
        _ = timeline.newlyStarted(at: 0)
        let currentFrame = sampleRate + 6_000
        let second = timeline.append(
            index: 1, text: "第二段。", frameCount: sampleRate,
            firstAudibleFrame: 0, currentFrame: currentFrame, lateSchedulingLead: schedulingLead
        )

        XCTAssertEqual(second.startFrame, currentFrame + schedulingLead)
        XCTAssertEqual(second.endFrame, currentFrame + schedulingLead + sampleRate)
        XCTAssertTrue(timeline.newlyStarted(at: currentFrame).isEmpty)
        XCTAssertTrue(timeline.newlyStarted(at: second.startFrame - 1).isEmpty)
        XCTAssertFalse(timeline.isPlaying(at: currentFrame))
        XCTAssertEqual(timeline.newlyStarted(at: second.startFrame).map(\.index), [1])
        XCTAssertTrue(timeline.isPlaying(at: second.startFrame))
    }

    func testAudibleOffsetDelaysStartAnnouncementAndPlayingState() {
        var timeline = SpeechPlaybackTimeline()
        let audibleOffset: Int64 = 2_400
        let segment = timeline.append(
            index: 0, text: "慢慢说。", frameCount: sampleRate,
            firstAudibleFrame: audibleOffset, currentFrame: nil, lateSchedulingLead: schedulingLead
        )

        XCTAssertEqual(segment.startFrame, 0)
        XCTAssertEqual(segment.audibleFrame, audibleOffset)
        XCTAssertTrue(timeline.newlyStarted(at: 0).isEmpty)
        XCTAssertFalse(timeline.isPlaying(at: 0))
        XCTAssertTrue(timeline.newlyStarted(at: audibleOffset - 1).isEmpty)
        XCTAssertFalse(timeline.isPlaying(at: audibleOffset - 1))
        XCTAssertEqual(timeline.newlyStarted(at: audibleOffset).map(\.index), [0])
        XCTAssertTrue(timeline.isPlaying(at: audibleOffset))
    }

    func testEachSegmentIsAnnouncedOnlyOnceEvenWhenClockIsPolledOrRewinds() {
        var timeline = SpeechPlaybackTimeline()
        _ = timeline.append(
            index: 0, text: "只说一次。", frameCount: sampleRate,
            firstAudibleFrame: 100, currentFrame: nil, lateSchedulingLead: schedulingLead
        )

        XCTAssertEqual(timeline.newlyStarted(at: 100).map(\.index), [0])
        XCTAssertTrue(timeline.newlyStarted(at: 100).isEmpty)
        XCTAssertTrue(timeline.newlyStarted(at: 200).isEmpty)
        XCTAssertTrue(timeline.newlyStarted(at: 0).isEmpty)
        XCTAssertTrue(timeline.newlyStarted(at: sampleRate * 2).isEmpty)
    }

    func testGapAndSecondSegmentsSilentPrerollAreNotPlaying() {
        var timeline = SpeechPlaybackTimeline()
        _ = timeline.append(
            index: 0, text: "第一段。", frameCount: sampleRate,
            firstAudibleFrame: 0, currentFrame: nil, lateSchedulingLead: schedulingLead
        )
        let second = timeline.append(
            index: 1, text: "第二段。", frameCount: sampleRate,
            firstAudibleFrame: 600, currentFrame: sampleRate + 3_000,
            lateSchedulingLead: schedulingLead
        )

        XCTAssertTrue(timeline.isPlaying(at: sampleRate - 1))
        XCTAssertFalse(timeline.isPlaying(at: sampleRate))
        XCTAssertFalse(timeline.isPlaying(at: second.startFrame - 1))
        XCTAssertFalse(timeline.isPlaying(at: second.startFrame))
        XCTAssertFalse(timeline.isPlaying(at: second.audibleFrame - 1))
        XCTAssertTrue(timeline.isPlaying(at: second.audibleFrame))
        XCTAssertTrue(timeline.isPlaying(at: second.endFrame - 1))
        XCTAssertFalse(timeline.isPlaying(at: second.endFrame))
    }

    func testCrossingSeveralBoundariesAnnouncesSegmentsInPlaybackOrder() {
        var timeline = SpeechPlaybackTimeline()
        for index in 0..<3 {
            _ = timeline.append(
                index: index, text: "第\(index)段。", frameCount: sampleRate,
                firstAudibleFrame: Int64(index * 100), currentFrame: nil,
                lateSchedulingLead: schedulingLead
            )
        }

        // A delayed monitor tick still reports all crossed starts, in order.
        let started = timeline.newlyStarted(at: sampleRate * 2 + 200)
        XCTAssertEqual(started.map(\.index), [0, 1, 2])
        XCTAssertEqual(started.map(\.text), ["第0段。", "第1段。", "第2段。"])
        XCTAssertTrue(timeline.newlyStarted(at: sampleRate * 3).isEmpty)
        XCTAssertFalse(timeline.isPlaying(at: sampleRate * 3))
    }

    func testLaterAppendDoesNotAnnounceEarlierSegmentAgain() {
        var timeline = SpeechPlaybackTimeline()
        _ = timeline.append(
            index: 0, text: "第一段。", frameCount: sampleRate,
            firstAudibleFrame: 0, currentFrame: nil, lateSchedulingLead: schedulingLead
        )
        XCTAssertEqual(timeline.newlyStarted(at: sampleRate - 1).map(\.index), [0])
        _ = timeline.append(
            index: 1, text: "第二段。", frameCount: sampleRate,
            firstAudibleFrame: 0, currentFrame: sampleRate / 2, lateSchedulingLead: schedulingLead
        )

        XCTAssertEqual(timeline.newlyStarted(at: sampleRate).map(\.index), [1])
        XCTAssertTrue(timeline.newlyStarted(at: sampleRate * 2).isEmpty)
    }

    func testAudibleOffsetIsClampedToValidFrames() {
        var timeline = SpeechPlaybackTimeline()
        let first = timeline.append(
            index: 0, text: "第一段。", frameCount: 100,
            firstAudibleFrame: -20, currentFrame: nil, lateSchedulingLead: schedulingLead
        )
        let second = timeline.append(
            index: 1, text: "第二段。", frameCount: 100,
            firstAudibleFrame: 150, currentFrame: nil, lateSchedulingLead: schedulingLead
        )

        XCTAssertEqual(first.audibleFrame, first.startFrame)
        XCTAssertEqual(second.audibleFrame, second.endFrame - 1)
    }

    func testEmptyTimelineNeverReportsPlaybackOrStartedSegments() {
        var timeline = SpeechPlaybackTimeline()
        XCTAssertTrue(timeline.newlyStarted(at: 0).isEmpty)
        XCTAssertTrue(timeline.newlyStarted(at: sampleRate).isEmpty)
        XCTAssertFalse(timeline.isPlaying(at: 0))
        XCTAssertFalse(timeline.isPlaying(at: sampleRate))
    }
}
