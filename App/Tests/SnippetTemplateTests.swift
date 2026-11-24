import XCTest
@testable import ToolsmithKit

final class SnippetTemplateTests: XCTestCase {
    private func t(_ body: String) -> SnippetTemplate { SnippetTemplate(body) }
    private func names(_ body: String) -> [String] { t(body).variables.map(\.name) }

    func testPlainTextHasNoVariables() {
        XCTAssertEqual(t("안녕하세요").pieces, [.text("안녕하세요")]); XCTAssertTrue(t("안녕하세요").variables.isEmpty)
    }
    func testVariablesInFirstAppearanceOrderOnce() {
        XCTAssertEqual(names("{이름}님, {포지션} 건으로 {이름}님께"), ["이름", "포지션"])
    }
    func testDefaultValueFirstOneWins() {
        XCTAssertEqual(t("{포지션:백엔드} {포지션:프론트}").variables, [.init(name: "포지션", defaultValue: "백엔드")])
    }
    func testSpecTable() {
        XCTAssertEqual(t("{{이름}}").pieces, [.text("{이름}")])
        XCTAssertEqual(t("{이름:}").variables, [.init(name: "이름", defaultValue: "")])
        XCTAssertEqual(t("{주소:https://a:b}").variables, [.init(name: "주소", defaultValue: "https://a:b")])
        XCTAssertEqual(t("{값:a}}b}").pieces, [.variable("값"), .text("}b}")])
        XCTAssertEqual(names("{ 이름 }{이름}"), ["이름"])
        for literal in ["{}", "{ }", "{:기본}", "{이름\n}", "{이름", "a } b"] {
            XCTAssertEqual(t(literal).pieces, [.text(literal)], literal)
        }
    }
    func testNestedOpenBraceIsLiteralThenParsesInner() {
        XCTAssertEqual(t("{a{b}").pieces, [.text("{a"), .variable("b")])
    }
    func testDefaultKeepsSpacesNameIsTrimmed() {
        XCTAssertEqual(t("{ 인사 : 안녕 }").variables, [.init(name: "인사", defaultValue: " 안녕 ")])
    }
    func testInnerSpacesMakeDifferentNames() { XCTAssertEqual(names("{내 이름}{내이름}"), ["내 이름", "내이름"]) }
    func testEveryNameIsAsked() {
        // No name fills itself in: 「날짜」 and 「클립보드」 are asked for like any other.
        XCTAssertEqual(names("{날짜} {클립보드} {이름}"), ["날짜", "클립보드", "이름"])
    }
    func testRender() {
        let text = t("{이름}님 {이름} {없음}{{x}}").render(values: ["이름": "가"])
        XCTAssertEqual(text, "가님 가 {x}")
    }
    func testValuesAreNotParsedAgain() {
        XCTAssertEqual(t("{a} {b}").render(values: ["a": "{b}\n{{", "b": "2"]), "{b}\n{{ 2")
    }
    func testPreviewMarksEmptyVariablesPending() {
        let runs = t("{이름}님 {포지션}").preview(values: ["이름": "가", "포지션": ""])
        XCTAssertEqual(runs, [.init(text: "가", kind: .filled), .init(text: "님 ", kind: .plain), .init(text: "포지션", kind: .pending)])
    }
}
