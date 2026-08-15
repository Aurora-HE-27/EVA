import XCTest
@testable import EVA

@MainActor
final class LocalLanguageModelTests: XCTestCase {
    func testStreamsACompleteChineseCompanionResponse() async throws {
        let model = LocalLanguageModel()
        let clock = ContinuousClock()
        let startedAt = clock.now
        var firstTokenAt: ContinuousClock.Instant?
        var response = ""

        var affectiveCore = AffectiveCore(profile: .defaultProfile)
        let turn = affectiveCore.observeUserMessage(
            "我升职了，但是办公室里没有一个人给我庆祝。"
        )
        let stream = try await model.streamResponse(
            to: turn.modelInput(userText: "我升职了，但是办公室里没有一个人给我庆祝。"),
            systemPrompt: AppState.systemPrompt
        )
        for try await token in stream {
            if firstTokenAt == nil, token.contains(where: { !$0.isWhitespace }) {
                firstTokenAt = clock.now
            }
            response += token
        }

        XCTAssertNotNil(firstTokenAt)
        XCTAssertGreaterThan(response.trimmingCharacters(in: .whitespacesAndNewlines).count, 4)
        var parser = EmotionStreamParser()
        let visibleResponse = parser.append(response) + (parser.flush() ?? "")
        XCTAssertNil(parser.directive)
        XCTAssertFalse(visibleResponse.contains("[[EVA"))
        XCTAssertFalse(visibleResponse.contains("eva_private_context"))
        XCTAssertFalse(visibleResponse.contains("user_message"))
        XCTAssertGreaterThan(visibleResponse.trimmingCharacters(in: .whitespacesAndNewlines).count, 4)
        let spokenResponse = VoiceResponsePolicy.continuousUtterance(
            generatedText: visibleResponse,
            fallback: "刚才那一下我没接住。",
            move: turn.move
        )
        XCTAssertLessThanOrEqual(
            spokenResponse.filter { "。！？!?".contains($0) }.count,
            2
        )
        print("EVA_BENCHMARK first_token=\(startedAt.duration(to: firstTokenAt ?? clock.now))")
        print("EVA_BENCHMARK total=\(startedAt.duration(to: clock.now))")
        print("EVA_RAW_RESPONSE \(response)")
        print("EVA_SPOKEN_RESPONSE \(spokenResponse)")
    }
}
