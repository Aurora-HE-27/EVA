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

    func testRemovesEmojiDecoratedActionLabelsInOnePass() {
        for input in ["（🙂微笑）你好", "(微笑🙂)你好", "【❤️抱抱】你好", "[🙂害羞]你好"] {
            XCTAssertEqual(SpokenTextNormalizer.normalize(input), "你好", input)
        }
    }

    func testRemovesMarkdownDecoratedActionLabelsInOnePass() {
        for input in ["（**微笑**）你好", "(**微笑**)你好", "【_叹气_】你好", "[~~眨眼~~]你好"] {
            XCTAssertEqual(SpokenTextNormalizer.normalize(input), "你好", input)
        }
    }

    func testDecoratedActionCleanupIsIdempotent() {
        let examples = [
            "（🙂微笑）你好",
            "（**微笑**）你好",
            "你好（**🙂害羞**），我们慢慢聊。",
            "先坐一会儿。【🙂_叹气_】我在听。",
            "看看 **这份资料**：[说明](https://example.com/a)（🙂点头）",
            "今天（8 月 5 日）休息 10 分钟。"
        ]
        for input in examples {
            let normalized = SpokenTextNormalizer.normalize(input)
            XCTAssertEqual(SpokenTextNormalizer.normalize(normalized), normalized, input)
        }
    }

    func testPreservesOrdinaryParenthesesAndNumbers() {
        let examples = [
            "今天（8 月 5 日）休息 10 分钟。",
            "这周(第 2 周)先完成 3 件事。",
            "我说的是（一个笑话），不是（难过的事）。",
            "请看【第 2 章】和[第 3 页]。",
            "数字是（123.45），编号是[8]。"
        ]
        for input in examples {
            XCTAssertEqual(SpokenTextNormalizer.normalize(input), input)
        }
    }
}
