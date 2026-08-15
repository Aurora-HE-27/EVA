import XCTest
@testable import EVA

final class AffectiveCoreTests: XCTestCase {
    private let profile = CompanionProfile.defaultProfile

    func testGoodNewsCreatesJoyThatPersistsAcrossTurns() {
        let start = Date(timeIntervalSince1970: 1_000)
        var core = AffectiveCore(profile: profile, at: start)
        let baselineValence = core.state.valence

        let goodNews = core.observeUserMessage("我升职了，真的太开心了！", at: start)
        XCTAssertEqual(goodNews.move, .celebrate)
        XCTAssertGreaterThan(goodNews.state.valence, baselineValence)

        let nextTurn = core.observeUserMessage("刚刚才收到通知。", at: start.addingTimeInterval(30))
        XCTAssertGreaterThan(nextTurn.state.valence, baselineValence)
    }

    func testQuestionIsAnsweredInsteadOfAutomaticallyCounselled() {
        var core = AffectiveCore(profile: profile, at: Date(timeIntervalSince1970: 2_000))
        let turn = core.observeUserMessage("你觉得我今晚吃什么？")

        XCTAssertEqual(turn.move, .answerDirectly)
        XCTAssertTrue(turn.modelInput(userText: "测试").contains("先直接回答问题"))
    }

    func testGoodNewsWithSocialDisappointmentKeepsMixedMeaning() {
        var core = AffectiveCore(profile: profile)
        let turn = core.observeUserMessage("我升职了，但是办公室里没有一个人给我庆祝。")

        XCTAssertEqual(turn.move, .mixedGoodNews)
        XCTAssertTrue(turn.modelInput(userText: "测试").contains("不要猜任何第三方动机"))
    }

    func testAnxietyRisesFromThreatAndNaturallyRelaxes() {
        let start = Date(timeIntervalSince1970: 3_000)
        var core = AffectiveCore(profile: profile, at: start)
        let baselineAnxiety = core.state.anxiety

        let threat = core.observeUserMessage("我很害怕，也不知道该怎么办，会不会出事？", at: start)
        XCTAssertGreaterThan(threat.state.anxiety, baselineAnxiety)

        let later = core.observeUserMessage("我回来了。", at: start.addingTimeInterval(3_600))
        XCTAssertLessThan(later.state.anxiety, threat.state.anxiety)
        XCTAssertGreaterThanOrEqual(later.state.anxiety, baselineAnxiety)
    }

    func testAbsenceDoesNotPunishTrustOrCloseness() {
        let start = Date(timeIntervalSince1970: 4_000)
        var core = AffectiveCore(profile: profile, at: start)
        let trust = core.state.trust
        let closeness = core.state.closeness

        let later = core.observeUserMessage(
            "我回来了。",
            at: start.addingTimeInterval(60 * 60 * 24 * 30)
        )

        XCTAssertEqual(later.state.trust, trust, accuracy: 0.000_001)
        XCTAssertEqual(later.state.closeness, closeness, accuracy: 0.000_001)
    }

    func testHostilityProducesCalmBoundaryRatherThanDependencyBehavior() {
        var core = AffectiveCore(profile: profile)
        let turn = core.observeUserMessage("闭嘴，你烦死我了。")

        XCTAssertEqual(turn.move, .setBoundary)
        XCTAssertTrue(turn.modelInput(userText: "测试").contains("不让用户内疚"))
    }

    func testAffectiveStateStoreRoundTripsAndClears() throws {
        let suiteName = "EVA.AffectiveCoreTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = AffectiveStateStore(defaults: defaults)
        let state = AffectiveState.baseline(for: .cheerful)

        XCTAssertNil(store.load())
        store.save(state)
        XCTAssertEqual(store.load(), state)
        store.clear()
        XCTAssertNil(store.load())
    }
}
