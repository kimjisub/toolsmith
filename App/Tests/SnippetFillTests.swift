import XCTest
@testable import ToolsmithKit

final class SnippetFillTests: XCTestCase {
    private func snippet(_ body: String) -> Snippet {
        Snippet(id: UUID(), name: "인사", body: body, createdAt: Fixture.now, updatedAt: Fixture.now)
    }
    func testStartsWithDefaultsAndFirstFocus() {
        let fill = SnippetFill(snippet: snippet("{이름}님 {포지션:백엔드}"), returnsToList: true)
        XCTAssertEqual(fill.values, ["", "백엔드"]); XCTAssertEqual(fill.focus, 0); XCTAssertEqual(fill.text, "님 백엔드")
    }
    func testSetValueAndFocusWraps() {
        var fill = SnippetFill(snippet: snippet("{a} {b} {c}"), returnsToList: true)
        fill.setValue("1", at: 0); fill.setValue("x", at: 9)   // 범위 밖은 무시
        fill.moveFocus(by: -1); XCTAssertEqual(fill.focus, 2)
        fill.moveFocus(by: 1); XCTAssertEqual(fill.focus, 0)
        fill.setFocus(1); XCTAssertEqual(fill.focus, 1); fill.setFocus(7); XCTAssertEqual(fill.focus, 1)
        XCTAssertEqual(fill.text, "1  ")
    }
    func testFillKeepsItsOwnTemplate() {
        var original = snippet("{이름}님")
        var fill = SnippetFill(snippet: original, returnsToList: false)
        original.body = "바뀜"; fill.setValue("가", at: 0)
        XCTAssertEqual(fill.text, "가님")   // 열릴 때의 내용
    }
    func testPressOnlyWhenTargetIsStillFrontmost() {
        XCTAssertTrue(SnippetPaste.shouldPress(target: 10, frontmost: 10))
        XCTAssertFalse(SnippetPaste.shouldPress(target: 10, frontmost: 11))
        XCTAssertFalse(SnippetPaste.shouldPress(target: nil, frontmost: 10)); XCTAssertFalse(SnippetPaste.shouldPress(target: 10, frontmost: nil))
    }
}
