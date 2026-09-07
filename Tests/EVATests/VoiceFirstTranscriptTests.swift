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
}
