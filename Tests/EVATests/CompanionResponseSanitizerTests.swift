import XCTest
@testable import EVA

final class CompanionResponseSanitizerTests: XCTestCase {
    func testRemovesLeadingStageDirectionAndEmoji() {
        let text = CompanionResponseSanitizer.normalize(
            "（轻轻拍拍你的肩膀）这确实让人很委屈。🤍"
        )

        XCTAssertEqual(text, "这确实让人很委屈。")
    }

    func testRemovesInlineStageDirection() {
        let text = CompanionResponseSanitizer.normalize(
            "我听见了。（沉默片刻，轻轻点头）我们慢一点。"
        )

        XCTAssertEqual(text, "我听见了。我们慢一点。")
    }
}
