import XCTest
@testable import EVA

final class VoiceFirstTranscriptTests: XCTestCase {
    func testReplyIsHiddenAndNotRestorableBeforeAudioStarts() {
        let reply = ChatMessage(role: .assistant, content: "今天过得怎么样？")
        let user = ChatMessage(role: .user, content: "晚上好")
        var transcript = VoiceFirstTranscript()
        transcript.prepare(reply.id)
        transcript.reveal(reply.id)

        XCTAssertTrue(transcript.concealedIDs.contains(reply.id))
        XCTAssertEqual(transcript.restorableMessages([user, reply]).map(\.id), [user.id])
    }

    func testActualPlaybackAllowsSavingThenDelayedReveal() {
        let reply = ChatMessage(role: .assistant, content: "我在听。")
        var transcript = VoiceFirstTranscript()
        transcript.prepare(reply.id)
        transcript.playbackStarted(reply.id)

        XCTAssertTrue(transcript.concealedIDs.contains(reply.id))
        XCTAssertEqual(transcript.restorableMessages([reply]).map(\.id), [reply.id])
        transcript.reveal(reply.id)
        XCTAssertFalse(transcript.concealedIDs.contains(reply.id))
        XCTAssertFalse(transcript.finish(reply.id))
    }

    func testCancelBeforePlaybackDiscardsButShortPlaybackKeepsReply() {
        let unheard = UUID()
        let heard = UUID()
        var transcript = VoiceFirstTranscript()
        transcript.prepare(unheard)
        transcript.prepare(heard)
        transcript.playbackStarted(heard)

        XCTAssertTrue(transcript.finish(unheard))
        XCTAssertFalse(transcript.finish(heard))
        XCTAssertTrue(transcript.concealedIDs.isEmpty)
    }

    func testReplayAndOldCompletionDoNotHideHistoryOrRevealNextReply() {
        let historical = ChatMessage(role: .assistant, content: "这是已经听过的话。")
        let next = ChatMessage(role: .assistant, content: "这是下一条。")
        var transcript = VoiceFirstTranscript()
        transcript.prepare(next.id)
        XCTAssertFalse(transcript.finish(historical.id))
        transcript.playbackStarted(historical.id)
        transcript.reveal(historical.id)
        XCTAssertFalse(transcript.finish(historical.id))

        XCTAssertTrue(transcript.concealedIDs.contains(next.id))
        XCTAssertEqual(transcript.restorableMessages([historical, next]).map(\.id), [historical.id])
    }

    func testPlanningSegmentsDoesNotMakeGeneratedTailRestorable() {
        let user = ChatMessage(role: .user, content: "我今天很累。")
        let reply = ChatMessage(role: .assistant, content: "先坐一会儿。今天发生什么了？")
        var transcript = VoiceFirstTranscript()
        transcript.prepare(reply.id)
        transcript.plan(["先坐一会儿。", "今天发生什么了？"], for: reply.id)

        XCTAssertEqual(transcript.heardContent(for: reply.id), "")
        XCTAssertNil(transcript.reveal(reply.id, through: 0))
        XCTAssertTrue(transcript.concealedIDs.contains(reply.id))
        XCTAssertEqual(transcript.restorableMessages([user, reply]), [user])
    }

    func testOnlyStartedSegmentIsSavedBeforeItsDelayedReveal() {
        let segments = ["这事真挺难受的。", "你接着说。", "我在听。"]
        let reply = ChatMessage(role: .assistant, content: segments.joined())
        var transcript = VoiceFirstTranscript()
        transcript.prepare(reply.id)
        transcript.plan(segments, for: reply.id)

        XCTAssertTrue(transcript.playbackStarted(reply.id, segmentIndex: 0))
        XCTAssertTrue(transcript.concealedIDs.contains(reply.id))
        XCTAssertEqual(transcript.heardContent(for: reply.id), segments[0])

        let saved = transcript.restorableMessages([reply])
        XCTAssertEqual(saved.count, 1)
        XCTAssertEqual(saved.first?.content, segments[0])
        XCTAssertEqual(saved.first?.id, reply.id)
        XCTAssertEqual(saved.first?.role, reply.role)
        XCTAssertEqual(saved.first?.createdAt, reply.createdAt)
        XCTAssertEqual(transcript.reveal(reply.id, through: 0), segments[0])
        XCTAssertFalse(transcript.concealedIDs.contains(reply.id))
    }

    func testSecondSegmentCommitsToHistoryWithoutRevealingItEarly() {
        let segments = ["真替你高兴。", "这次是你自己争取来的。", "今晚怎么庆祝？"]
        let reply = ChatMessage(role: .assistant, content: "")
        var transcript = VoiceFirstTranscript()
        transcript.prepare(reply.id)
        transcript.plan(segments, for: reply.id)

        XCTAssertTrue(transcript.playbackStarted(reply.id, segmentIndex: 0))
        XCTAssertEqual(transcript.reveal(reply.id, through: 0), segments[0])
        XCTAssertTrue(transcript.playbackStarted(reply.id, segmentIndex: 1))

        let heardPrefix = segments.prefix(2).joined()
        XCTAssertEqual(transcript.heardContent(for: reply.id), heardPrefix)
        XCTAssertEqual(transcript.restorableMessages([reply]).first?.content, heardPrefix)
        XCTAssertEqual(transcript.reveal(reply.id, through: 0), segments[0])
        XCTAssertNil(transcript.reveal(reply.id, through: 2))
        XCTAssertEqual(transcript.reveal(reply.id, through: 1), heardPrefix)
    }

    func testSegmentsMustStartInOrderAndCannotStartTwice() {
        let replyID = UUID()
        var transcript = VoiceFirstTranscript()
        transcript.prepare(replyID)
        transcript.plan(["第一句。", "第二句。"], for: replyID)

        XCTAssertFalse(transcript.playbackStarted(replyID, segmentIndex: -1))
        XCTAssertFalse(transcript.playbackStarted(replyID, segmentIndex: 1))
        XCTAssertFalse(transcript.playbackStarted(replyID, segmentIndex: 2))
        XCTAssertEqual(transcript.heardContent(for: replyID), "")
        XCTAssertTrue(transcript.playbackStarted(replyID, segmentIndex: 0))
        XCTAssertFalse(transcript.playbackStarted(replyID, segmentIndex: 0))
        XCTAssertTrue(transcript.playbackStarted(replyID, segmentIndex: 1))
        XCTAssertFalse(transcript.playbackStarted(replyID, segmentIndex: 1))
        XCTAssertEqual(transcript.heardContent(for: replyID), "第一句。第二句。")
    }

    func testLateRevealCannotShrinkAlreadyVisiblePrefix() {
        let replyID = UUID()
        var transcript = VoiceFirstTranscript()
        transcript.prepare(replyID)
        transcript.plan(["第一句。", "第二句。"], for: replyID)
        transcript.playbackStarted(replyID, segmentIndex: 0)
        transcript.playbackStarted(replyID, segmentIndex: 1)

        XCTAssertNil(transcript.reveal(replyID, through: -1))
        XCTAssertEqual(transcript.reveal(replyID, through: 1), "第一句。第二句。")
        XCTAssertEqual(transcript.reveal(replyID, through: 0), "第一句。第二句。")
        XCTAssertEqual(transcript.reveal(replyID), "第一句。第二句。")
    }

    func testPlanCannotBeRewrittenAfterPlaybackStarts() {
        let replyID = UUID()
        var transcript = VoiceFirstTranscript()
        transcript.prepare(replyID)
        transcript.plan(["原来的第一句。", "原来的第二句。"], for: replyID)
        transcript.playbackStarted(replyID, segmentIndex: 0)
        transcript.plan(["不能替换已开口的内容。"], for: replyID)

        XCTAssertEqual(transcript.heardContent(for: replyID), "原来的第一句。")
        XCTAssertTrue(transcript.playbackStarted(replyID, segmentIndex: 1))
        XCTAssertEqual(transcript.reveal(replyID), "原来的第一句。原来的第二句。")
    }

    func testEmptyPlanRemainsUnheardAndIsDiscarded() {
        let reply = ChatMessage(role: .assistant, content: "")
        var transcript = VoiceFirstTranscript()
        transcript.prepare(reply.id)
        transcript.plan([], for: reply.id)

        XCTAssertFalse(transcript.playbackStarted(reply.id, segmentIndex: 0))
        XCTAssertNil(transcript.reveal(reply.id))
        XCTAssertTrue(transcript.restorableMessages([reply]).isEmpty)
        XCTAssertTrue(transcript.finish(reply.id))
        XCTAssertNil(transcript.heardContent(for: reply.id))
    }

    func testCancelBeforeFirstSegmentDiscardsReplyAndRejectsLateCallbacks() {
        let replyID = UUID()
        var transcript = VoiceFirstTranscript()
        transcript.prepare(replyID)
        transcript.plan(["还没有说出口。", "这句也不应留下。"], for: replyID)

        XCTAssertTrue(transcript.finish(replyID))
        XCTAssertFalse(transcript.playbackStarted(replyID, segmentIndex: 0))
        XCTAssertNil(transcript.reveal(replyID, through: 0))
        XCTAssertNil(transcript.heardContent(for: replyID))
        XCTAssertFalse(transcript.concealedIDs.contains(replyID))
    }

    func testInterruptedReplyIsFinalizedWithHeardPrefixBeforePlanIsCleared() {
        var reply = ChatMessage(role: .assistant, content: "已经开口。尚未播放。")
        var transcript = VoiceFirstTranscript()
        transcript.prepare(reply.id)
        transcript.plan(["已经开口。", "尚未播放。"], for: reply.id)
        transcript.playbackStarted(reply.id, segmentIndex: 0)

        // The caller commits the heard prefix before finish removes transient state.
        reply.content = transcript.heardContent(for: reply.id) ?? ""
        XCTAssertFalse(transcript.finish(reply.id))
        XCTAssertEqual(transcript.restorableMessages([reply]).first?.content, "已经开口。")
        XCTAssertFalse(transcript.playbackStarted(reply.id, segmentIndex: 1))
        XCTAssertNil(transcript.reveal(reply.id, through: 1))
        XCTAssertNil(transcript.heardContent(for: reply.id))
    }

    func testFinishedReplyCallbacksCannotMutateAnotherActivePlan() {
        let previousID = UUID()
        let next = ChatMessage(role: .assistant, content: "新回复的隐藏草稿。")
        var transcript = VoiceFirstTranscript()
        transcript.prepare(previousID)
        transcript.plan(["旧回复。", "旧回复未播放尾巴。"], for: previousID)
        transcript.playbackStarted(previousID, segmentIndex: 0)
        XCTAssertFalse(transcript.finish(previousID))
        transcript.prepare(next.id)
        transcript.plan(["新回复。", "新回复的尾巴。"], for: next.id)

        XCTAssertFalse(transcript.playbackStarted(previousID, segmentIndex: 1))
        XCTAssertNil(transcript.reveal(previousID, through: 0))
        XCTAssertFalse(transcript.finish(previousID))
        XCTAssertTrue(transcript.concealedIDs.contains(next.id))
        XCTAssertEqual(transcript.heardContent(for: next.id), "")
        XCTAssertTrue(transcript.restorableMessages([next]).isEmpty)
        XCTAssertTrue(transcript.playbackStarted(next.id, segmentIndex: 0))
        XCTAssertEqual(transcript.reveal(next.id, through: 0), "新回复。")
    }

    func testReplayCannotCreatePlanOrChangeRestoredHistoricalText() {
        let historical = ChatMessage(role: .assistant, content: "完整的历史回复。")
        let next = ChatMessage(role: .assistant, content: "尚未播放的新回复。")
        var transcript = VoiceFirstTranscript()
        transcript.prepare(next.id)
        transcript.plan(["新的第一句。", "新的第二句。"], for: next.id)

        transcript.plan(["不应替换历史回复。"], for: historical.id)
        XCTAssertFalse(transcript.playbackStarted(historical.id, segmentIndex: 0))
        XCTAssertNil(transcript.reveal(historical.id, through: 0))
        XCTAssertNil(transcript.heardContent(for: historical.id))
        XCTAssertFalse(transcript.finish(historical.id))
        XCTAssertEqual(transcript.restorableMessages([historical, next]), [historical])
        XCTAssertTrue(transcript.concealedIDs.contains(next.id))
    }
}
