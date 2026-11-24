import XCTest
@testable import ToolsmithKit

final class MatcherTests: XCTestCase {
    func testComposingSyllableMatches() {
        XCTAssertEqual(Matcher.score(query: "ㅇ", candidate: "왼쪽 절반")?.kind, .prefix)
        XCTAssertEqual(Matcher.score(query: "오", candidate: "왼쪽 절반")?.kind, .prefix)
        XCTAssertEqual(Matcher.score(query: "외", candidate: "왼쪽 절반")?.kind, .prefix)
        XCTAssertEqual(Matcher.score(query: "왼", candidate: "왼쪽 절반")?.kind, .prefix)
    }

    func testWordPrefixAndSubstring() {
        XCTAssertEqual(Matcher.score(query: "절반", candidate: "왼쪽 절반"), MatchScore(kind: .wordPrefix, position: 1))
        XCTAssertEqual(Matcher.score(query: "립보", candidate: "클립보드")?.kind, .substring)
    }

    func testInitials() {
        XCTAssertEqual(Matcher.score(query: "ㅋㄹ", candidate: "클립보드")?.kind, .initials)
        XCTAssertEqual(Matcher.score(query: "vsc", candidate: "Visual Studio Code")?.kind, .initials)
        XCTAssertEqual(Matcher.score(query: "ㅇㅉㅈ", candidate: "왼쪽 절반")?.kind, .initials)
    }

    func testCaseAndNoMatch() {
        XCTAssertEqual(Matcher.score(query: "SLA", candidate: "Slack")?.kind, .prefix)
        XCTAssertNil(Matcher.score(query: "왼", candidate: "오른쪽 절반"))
        XCTAssertNil(Matcher.score(query: "", candidate: "Slack"))
        XCTAssertNil(Matcher.score(query: "   ", candidate: "Slack"))
    }

    func testOrdering() {
        XCTAssertLessThan(MatchScore(kind: .prefix, position: 0), MatchScore(kind: .wordPrefix, position: 1))
        XCTAssertLessThan(MatchScore(kind: .wordPrefix, position: 1), MatchScore(kind: .wordPrefix, position: 2))
        XCTAssertLessThan(MatchScore(kind: .substring, position: 9), MatchScore(kind: .initials, position: 0))
    }
}
