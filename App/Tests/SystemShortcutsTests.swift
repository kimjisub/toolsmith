import XCTest
@testable import ToolsmithKit

final class SystemShortcutsTests: XCTestCase {
    func testParsesEnabledOnly() {
        let plist: [String: Any] = [
            "64": ["enabled": true, "value": ["parameters": [32, 49, 1_048_576], "type": "standard"]],
            "65": ["enabled": false, "value": ["parameters": [32, 49, 1_572_864], "type": "standard"]],
        ]
        XCTAssertEqual(SystemShortcuts.parse(plist), [KeyCombo(keyCode: 49, modifiers: [.command])])
    }

    func testIgnoresMalformedEntries() {
        let plist: [String: Any] = ["1": "nope", "2": ["enabled": true], "3": ["enabled": true, "value": ["parameters": [65535, 65535, 0]]]]
        XCTAssertEqual(SystemShortcuts.parse(plist), [])
    }
}
