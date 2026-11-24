import XCTest
@testable import ToolsmithKit

final class KeyComboTests: XCTestCase {
    func testDisplay() {
        XCTAssertEqual(KeyCombo(keyCode: 49, modifiers: [.option]).display, "⌥Space")
        XCTAssertEqual(KeyCombo(keyCode: 123, modifiers: [.option, .control]).display, "⌃⌥←")
        XCTAssertEqual(KeyCombo(keyCode: 36, modifiers: [.control, .option]).display, "⌃⌥↵")
        XCTAssertEqual(KeyCombo(keyCode: 9, modifiers: [.command, .shift]).display, "⇧⌘V")
        XCTAssertEqual(KeyCombo(keyCode: 43, modifiers: [.option]).display, "⌥,")
    }

    func testDisplayParts() {
        XCTAssertEqual(KeyCombo(keyCode: 123, modifiers: [.option, .control]).displayParts, ["⌃", "⌥", "←"])
    }

    func testValidity() {
        XCTAssertFalse(KeyCombo(keyCode: 9, modifiers: []).isValid)
        XCTAssertFalse(KeyCombo(keyCode: 9, modifiers: [.shift]).isValid)
        XCTAssertTrue(KeyCombo(keyCode: 9, modifiers: [.option]).isValid)
        XCTAssertTrue(KeyCombo(keyCode: 96, modifiers: []).isValid)
    }

    func testCodableRoundTrip() throws {
        let combo = KeyCombo(keyCode: 123, modifiers: [.control, .option])
        XCTAssertEqual(try JSONDecoder().decode(KeyCombo.self, from: JSONEncoder().encode(combo)), combo)
    }
}
