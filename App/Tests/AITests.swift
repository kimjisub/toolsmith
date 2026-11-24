import XCTest
@testable import ToolsmithKit

@MainActor final class LauncherAITests: XCTestCase {
    var model: LauncherModel!
    var log: RunLog!

    override func setUp() async throws {
        log = RunLog()
        let usage = UsageLog(fileURL: tempFile())
        let engine = LauncherEngine(sources: [StubSource(list: Fixture.commands(log: log))], usage: usage, now: { Fixture.now })
        engine.reload()
        model = LauncherModel(engine: engine, usage: usage, now: { Fixture.now })
    }

    func testOnlyWebLinksOpen() {
        XCTAssertNotNil(WebLink.url("https://example.com/a"))
        XCTAssertNotNil(WebLink.url("HTTP://example.com"))
        XCTAssertNil(WebLink.url("file:///etc/passwd"))
        XCTAssertNil(WebLink.url("x-apple-systempreferences:com.apple.preference.security"))
        XCTAssertNil(WebLink.url("javascript:alert(1)"))
        XCTAssertNil(WebLink.url("https://"))
    }

    func testAIRowIsOfferedButNeverSelectedByItself() {
        model.query = "왼"
        XCTAssertTrue(model.showsAIRow); XCTAssertEqual(model.selectedID, "window.left-half")
        model.query = "zzzz"
        XCTAssertTrue(model.showsAIRow); XCTAssertNil(model.selectedID)
        XCTAssertEqual(model.submit(), .nothing)          // Return with no results sends nothing anywhere
        model.query = ""
        XCTAssertFalse(model.showsAIRow)
    }

    func testReachingTheAIRowTakesADeliberateStep() {
        model.query = "왼"
        model.moveSelection(by: 1); model.moveSelection(by: 1)           // past the last command
        XCTAssertEqual(model.selectedID, LauncherModel.aiRowID)
        XCTAssertEqual(model.submit(), .ask("왼"))
        model.query = "zzzz"; model.selectAIRow()                        // Tab
        XCTAssertEqual(model.submit(), .ask("zzzz"))
        model.moveSelection(by: -1)
        XCTAssertEqual(model.selectedID, LauncherModel.aiRowID)          // nothing above it: stays
    }

    func testNumbersNeverRunTheAIRow() {
        model.query = "zzzz"
        XCTAssertFalse(model.activate(number: 1))
        model.query = "왼"
        XCTAssertFalse(model.activate(number: 3))                        // two commands; the AI row has no number
    }

    func testSubmitRunsTheSelectedCommand() {
        model.query = "sla"
        XCTAssertEqual(model.submit(), .ran("app:slack")); XCTAssertEqual(log.ids, ["app:slack"])
    }

    func testDotAtTheStartSwitchesToAI() {
        model.query = "."
        XCTAssertEqual(model.mode, .ai); XCTAssertEqual(model.query, "")  // the dot is not kept as text
        XCTAssertTrue(model.visibleIDs.isEmpty); XCTAssertFalse(model.showsAIRow)
        XCTAssertEqual(model.submit(), .nothing)                          // nothing to ask yet
        model.query = "오늘 원달러 환율"
        XCTAssertEqual(model.submit(), .ask("오늘 원달러 환율"))
        XCTAssertTrue(log.ids.isEmpty)
    }

    func testDotElsewhereIsJustText() {
        model.query = "a"; model.query = "a."
        XCTAssertEqual(model.mode, .commands); XCTAssertEqual(model.query, "a.")
    }

    func testPastingDotQuestionIntoEmptyFieldSwitchesAndKeepsTheQuestion() {
        model.query = ".서울 날씨"
        XCTAssertEqual(model.mode, .ai); XCTAssertEqual(model.query, "서울 날씨")
    }

    func testLeavingAIMode() {
        model.query = "."; model.exitAIMode()
        XCTAssertEqual(model.mode, .commands)
        model.query = "."; model.query = "질문"; model.reset()
        XCTAssertEqual(model.mode, .commands); XCTAssertEqual(model.query, "")
    }

    func testAskFromAIRowEntersAIModeForFollowUps() {
        model.query = "zzzz"; model.selectAIRow()
        XCTAssertEqual(model.submit(), .ask("zzzz"))
        model.enterAIMode()
        XCTAssertEqual(model.mode, .ai); XCTAssertEqual(model.query, "")
    }
}

final class AIStreamTests: XCTestCase {
    func testTextDeltasAndDone() {
        var parser = AIStreamParser()
        XCTAssertEqual(parser.feed(#"data: {"choices":[{"delta":{"content":"안녕"}}]}"#), [.text("안녕")])
        XCTAssertEqual(parser.feed(#"data: {"choices":[{"delta":{"content":""},"finish_reason":"stop"}],"usage":{"total_tokens":3}}"#), [])
        XCTAssertEqual(parser.feed("data: [DONE]"), [.done])
    }

    func testIgnoresCommentsBlankLinesAndGarbage() {
        var parser = AIStreamParser()
        XCTAssertEqual(parser.feed(": OPENROUTER PROCESSING"), [])
        XCTAssertEqual(parser.feed(""), [])
        XCTAssertEqual(parser.feed("event: ping"), [])
        XCTAssertEqual(parser.feed("data: {not json"), [])
    }

    func testMidStreamError() {
        var parser = AIStreamParser()
        let events = parser.feed(#"data: {"error":{"code":502,"message":"Provider disconnected unexpectedly"},"choices":[{"delta":{"content":""},"finish_reason":"error"}]}"#)
        XCTAssertEqual(events, [.error("Provider disconnected unexpectedly")])
    }

    func testCitationsFromDeltaOrMessage() {
        var parser = AIStreamParser()
        let delta = #"data: {"choices":[{"delta":{"content":"","annotations":[{"type":"url_citation","url_citation":{"url":"https://a.example/x","title":"A"}}]}}]}"#
        XCTAssertEqual(parser.feed(delta), [.citations([Citation(title: "A", url: "https://a.example/x")])])
        let message = #"data: {"choices":[{"message":{"content":"","annotations":[{"type":"url_citation","url_citation":{"url":"https://b.example/y"}}]}}]}"#
        XCTAssertEqual(parser.feed(message), [.citations([Citation(title: "b.example", url: "https://b.example/y")])])
    }

    func testCitationMergeDropsDuplicates() {
        let a = Citation(title: "A", url: "https://a.example/x")
        XCTAssertEqual(Citation.merge([a], [a, Citation(title: "B", url: "https://b.example")]).map(\.url), ["https://a.example/x", "https://b.example"])
    }

    func testCitationsFromMarkdownLinksWhenNoneWereSent() {
        let text = "환율은 1,380원입니다 ([investing.com](https://investing.com/usd-krw)). 자세히는 [한국은행](https://bok.or.kr) 참고. [investing.com](https://investing.com/usd-krw)"
        XCTAssertEqual(Citation.fromMarkdownLinks(in: text), [
            Citation(title: "investing.com", url: "https://investing.com/usd-krw"),
            Citation(title: "한국은행", url: "https://bok.or.kr"),
        ])
        XCTAssertEqual(Citation.fromMarkdownLinks(in: "링크 없음 [x](mailto:a@b.c)"), [])
    }

    func testRequestBody() throws {
        let data = AIRequest.body(model: "anthropic/claude-haiku-5.5", system: "짧게 답한다",
                                  messages: [AIMessage(role: .user, text: "질문1"), AIMessage(role: .assistant, text: "답1"), AIMessage(role: .user, text: "질문2")])
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["model"] as? String, "anthropic/claude-haiku-5.5")
        XCTAssertEqual(json["stream"] as? Bool, true)
        let plugins = try XCTUnwrap(json["plugins"] as? [[String: Any]])
        XCTAssertEqual(plugins.first?["id"] as? String, "web")
        let messages = try XCTUnwrap(json["messages"] as? [[String: String]])
        XCTAssertEqual(messages.map { $0["role"] ?? "" }, ["system", "user", "assistant", "user"])
        XCTAssertEqual(messages.last?["content"], "질문2")
    }

    func testHTTPErrorMessages() {
        XCTAssertEqual(AIRequest.errorMessage(status: 401, body: Data()), "OpenRouter 키가 맞지 않습니다. 설정의 AI 검색에서 다시 넣어 주세요.")
        XCTAssertEqual(AIRequest.errorMessage(status: 402, body: Data()), "OpenRouter 크레딧이 부족합니다.")
        XCTAssertEqual(AIRequest.errorMessage(status: 429, body: Data()), "요청이 너무 많습니다. 잠시 뒤에 다시 물어 주세요.")
        XCTAssertEqual(AIRequest.errorMessage(status: 400, body: Data(#"{"error":{"code":400,"message":"Invalid model specified"}}"#.utf8)), "Invalid model specified")
        XCTAssertEqual(AIRequest.errorMessage(status: 503, body: Data("oops".utf8)), "AI 가 답하지 못했습니다 (503).")
    }
}
