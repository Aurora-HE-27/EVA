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

        let stream = try await model.streamResponse(
            to: "我今天有点累，又不太想跟别人说。",
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
        XCTAssertNotNil(parser.directive)
        XCTAssertFalse(visibleResponse.contains("[[EVA"))
        XCTAssertGreaterThan(visibleResponse.trimmingCharacters(in: .whitespacesAndNewlines).count, 4)
        print("EVA_BENCHMARK first_token=\(startedAt.duration(to: firstTokenAt ?? clock.now))")
        print("EVA_BENCHMARK total=\(startedAt.duration(to: clock.now))")
        print("EVA_RESPONSE \(response)")
    }
}
