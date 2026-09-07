import XCTest
@testable import EVA

final class SpokenReplySegmenterTests: XCTestCase {
    private let firstSentence = "今天看到你终于把那件惦记很久的事情做完了，我也跟着松了一口气。"
    private let secondSentence = "晚上我们就慢慢聊一会儿，你想说路上发生的小事也好，什么都不说也没有关系。"

    func testKeepsShortReplyAndItsProsodyContextTogether() {
        let text = "嗯。我知道你今天有点累，我们慢慢聊，不着急。"
        XCTAssertEqual(SpokenReplySegmenter.segments(for: text), [text])
    }

    func testSplitsLongReplyOnlyAtCompleteSentenceBoundary() {
        let text = firstSentence + secondSentence
        let segments = SpokenReplySegmenter.segments(for: text)
        XCTAssertEqual(segments, [firstSentence, secondSentence])
        XCTAssertEqual(segments.joined(), text)
    }

    func testSixtyCharacterThresholdKeepsShortRepliesIntact() {
        let sentence = String(repeating: "好", count: 29) + "。"
        XCTAssertEqual(SpokenReplySegmenter.segments(for: sentence + sentence), [sentence + sentence])
        let longerSentence = String(repeating: "好", count: 30) + "。"
        XCTAssertEqual(SpokenReplySegmenter.segments(for: sentence + longerSentence), [sentence, longerSentence])
    }

    func testMergesVeryShortOpeningReactionWithFollowingSentence() {
        let text = "嗯。" + firstSentence + secondSentence
        XCTAssertEqual(SpokenReplySegmenter.segments(for: text), ["嗯。" + firstSentence, secondSentence])
    }

    func testKeepsVeryShortClosingReactionWithPreviousSentence() {
        let text = firstSentence + secondSentence + "好呀！"
        XCTAssertEqual(SpokenReplySegmenter.segments(for: text), [firstSentence, secondSentence + "好呀！"])
    }

    func testNeverSplitsAtCommasOrMissingPunctuation() {
        let unpunctuated = String(repeating: "我们慢慢聊", count: 20)
        let commaSeparated = String(repeating: "我们慢慢聊，", count: 20)
        XCTAssertEqual(SpokenReplySegmenter.segments(for: unpunctuated), [unpunctuated])
        XCTAssertEqual(SpokenReplySegmenter.segments(for: commaSeparated), [commaSeparated])
    }

    func testKeepsQuestionExclamationClusterAndClosingQuoteTogether() {
        let quoted = "你当时居然还笑着跟我说：“这么多事情真的都是你一个人慢慢做完的？！”"
        let text = quoted + secondSentence
        XCTAssertEqual(SpokenReplySegmenter.segments(for: text), [quoted, secondSentence])

        let asciiQuote = "\"I really did not expect you to remember all those little details?!\""
        let followup = " You made an ordinary evening feel like something I want to remember."
        let asciiSegments = SpokenReplySegmenter.segments(for: asciiQuote + followup)
        XCTAssertEqual(asciiSegments, [asciiQuote + " ", String(followup.dropFirst())])
    }

    func testDoesNotSplitInsideAnUnfinishedQuotationOrParenthesis() {
        let quoted = "她说：“" + firstSentence + secondSentence + "”"
        let parenthesized = "（" + firstSentence + secondSentence + "）"
        XCTAssertEqual(SpokenReplySegmenter.segments(for: quoted), [quoted])
        XCTAssertEqual(SpokenReplySegmenter.segments(for: parenthesized), [parenthesized])
    }

    func testKeepsNestedClosingQuotesWithTheirSentence() {
        let quoted = "她认真告诉我：“我还记得你那天小声问的那句‘现在终于可以休息一下了吗？’”"
        XCTAssertEqual(SpokenReplySegmenter.segments(for: quoted + secondSentence), [quoted, secondSentence])
    }

    func testPreservesWhitespaceAndEmojiWithoutTakingOverTextCleaning() {
        let text = "  " + firstSentence + "\n\n" + secondSentence + " 🤍  "
        let segments = SpokenReplySegmenter.segments(for: text)
        XCTAssertEqual(segments.count, 2)
        XCTAssertEqual(segments.joined(), text)
        XCTAssertTrue(segments.last?.contains("🤍") == true)
        XCTAssertEqual(SpokenReplySegmenter.segments(for: "🤍"), ["🤍"])
    }

    func testNeverProducesMoreThanTwoSegmentsOrLosesCharacters() {
        let text = String(repeating: firstSentence, count: 8)
        let segments = SpokenReplySegmenter.segments(for: text)
        XCTAssertEqual(segments.count, 2)
        XCTAssertEqual(segments.joined(), text)
        XCTAssertTrue(segments.allSatisfy { !$0.isEmpty })
    }

    func testDoesNotTreatDecimalsOrHesitationAsSentenceBoundaries() {
        let text = String(repeating: "第3.14次想起这件事...", count: 8)
        XCTAssertEqual(SpokenReplySegmenter.segments(for: text), [text])
    }

    func testEmptyOrWhitespaceOnlyInputHasNoSpokenSegments() {
        XCTAssertEqual(SpokenReplySegmenter.segments(for: ""), [])
        XCTAssertEqual(SpokenReplySegmenter.segments(for: " \n\t "), [])
    }
}
