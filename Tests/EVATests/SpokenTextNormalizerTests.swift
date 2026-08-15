import XCTest
@testable import EVA

final class SpokenTextNormalizerTests: XCTestCase {
    func testRemovesEmojiAndActionLabelsWithoutChangingVisibleMessage() {
        XCTAssertEqual(
            SpokenTextNormalizer.normalize("抱抱你 🤗（微笑）我们慢慢来。❤️"),
            "抱抱你 我们慢慢来。"
        )
    }

    func testKeepsLinkLabelButDoesNotSpeakURLOrMarkdown() {
        XCTAssertEqual(
            SpokenTextNormalizer.normalize("看看 **这份资料**：[说明](https://example.com/a)"),
            "看看 这份资料：说明"
        )
    }

    func testDoesNotRemoveOrdinaryChineseOrNumbers() {
        XCTAssertEqual(
            SpokenTextNormalizer.normalize("今天是 8 月 5 日，先休息 10 分钟。"),
            "今天是 8 月 5 日，先休息 10 分钟。"
        )
    }
}
