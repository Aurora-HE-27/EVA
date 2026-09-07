import XCTest
@testable import EVA

@MainActor
final class LocalLanguageModelTests: XCTestCase {
    func testDiscardedTurnRestoresOnlyConfirmedHistory() async throws {
        let model = LocalLanguageModel()
        let instruction = "记住用户约定的暗号。被问到暗号时，只回答暗号，不要解释。"
        let abandoned = try await model.streamResponse(
            to: "我们约定暗号是红苹果。只回复记住了。",
            systemPrompt: instruction
        )
        for try await _ in abandoned {}

        model.invalidateConversation()
        let restored = try await model.streamResponse(
            to: "我们约定的暗号是什么？只回答暗号。",
            systemPrompt: instruction,
            history: [
                ChatMessage(role: .user, content: "我们约定暗号是蓝鲸。"),
                ChatMessage(role: .assistant, content: "记住了。")
            ]
        )
        var response = ""
        for try await token in restored { response += token }

        XCTAssertTrue(response.contains("蓝鲸"), response)
        XCTAssertFalse(response.contains("红苹果"), response)
        XCTAssertEqual(model.loadState, .ready)
    }

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
