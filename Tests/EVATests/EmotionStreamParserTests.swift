import XCTest
@testable import EVA

final class EmotionStreamParserTests: XCTestCase {
    func testParsesDirectiveAcrossFragmentsAndHidesIt() {
        var parser = EmotionStreamParser()

        XCTAssertEqual(parser.append("[[EVA emotion=con"), "")
        XCTAssertEqual(
            parser.append("cerned valence=-0.2 arousal=0.3 intensity=0.6]]\n我在听。"),
            "我在听。"
        )
        XCTAssertEqual(parser.directive?.emotion, .concerned)
        XCTAssertEqual(parser.directive?.valence, -0.2)
        XCTAssertEqual(parser.directive?.arousal, 0.3)
        XCTAssertEqual(parser.directive?.intensity, 0.6)
    }

    func testPreservesOrdinaryTextWhenDirectiveIsMissing() {
        var parser = EmotionStreamParser()

        XCTAssertEqual(parser.append("普通回复第一行\n第二行"), "普通回复第一行\n第二行")
        XCTAssertNil(parser.directive)
        XCTAssertNil(parser.flush())
    }

    func testFlushPreservesShortReplyWithoutNewline() {
        var parser = EmotionStreamParser()

        XCTAssertEqual(parser.append("你好呀"), "")
        XCTAssertEqual(parser.flush(), "你好呀")
    }
}
