import XCTest
@testable import EVA

final class VoiceResponsePolicyTests: XCTestCase {
    func testKeepsMultipleSentencesInOneContinuousUtterance() {
        let utterance = VoiceResponsePolicy.continuousUtterance(
            generatedText: "我听见了。我们先慢一点，再一起想办法。",
            fallback: "我在听。"
        )

        XCTAssertEqual(utterance, "我听见了。我们先慢一点，再一起想办法。")
    }

    func testUsesCleanFallbackWhenGeneratedResponseIsEmpty() {
        let utterance = VoiceResponsePolicy.continuousUtterance(
            generatedText: "  🤍  ",
            fallback: "我在听。🤍"
        )

        XCTAssertEqual(utterance, "我在听。")
    }

    func testFriendReactionStopsBeforeConsultingStyleAppendix() {
        let utterance = VoiceResponsePolicy.continuousUtterance(
            generatedText: "先认真恭喜你！没人庆祝确实挺扫兴的。你可以喝杯热茶。要不要分析一下原因？",
            fallback: "我在听。",
            move: .mixedGoodNews
        )

        XCTAssertEqual(utterance, "先认真恭喜你！没人庆祝确实挺扫兴的。")
    }
}
