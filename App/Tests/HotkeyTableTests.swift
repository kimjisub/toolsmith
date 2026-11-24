import XCTest
@testable import ToolsmithKit

final class HotkeyTableTests: XCTestCase {
    let left = KeyCombo(keyCode: 123, modifiers: [.control, .option])
    let space = KeyCombo(keyCode: 49, modifiers: [.option])

    func testDefaultsHaveLauncher() {
        XCTAssertEqual(HotkeyTable.defaults.combo(for: HotkeyID.openLauncher), space)
    }

    func testAssignTakenComboLeavesTableUntouched() {
        var t = HotkeyTable.defaults; XCTAssertEqual(t.assign(left, to: "window.left-half"), .assigned)
        let before = t
        XCTAssertEqual(t.assign(left, to: "window.right-half"), .taken(by: "window.left-half"))
        XCTAssertEqual(t, before)
    }

    func testAssignReplacesOwnCombo() {
        var t = HotkeyTable.defaults; _ = t.assign(left, to: "window.left-half")
        let other = KeyCombo(keyCode: 124, modifiers: [.control, .option])
        XCTAssertEqual(t.assign(other, to: "window.left-half"), .assigned)
        XCTAssertNil(t.owner(of: left)); XCTAssertEqual(t.combo(for: "window.left-half"), other)
        XCTAssertEqual(t.assign(other, to: "window.left-half"), .assigned)
    }

    func testReassignMovesAndClearsPreviousOwner() {
        var t = HotkeyTable.defaults; _ = t.assign(left, to: "window.left-half")
        t.reassign(left, to: "window.right-half")
        XCTAssertNil(t.combo(for: "window.left-half")); XCTAssertEqual(t.owner(of: left), "window.right-half")
    }

    func testReassigningLauncherComboAwayIsRefused() {
        var t = HotkeyTable.defaults
        XCTAssertEqual(t.assign(space, to: "window.left-half"), .taken(by: HotkeyID.openLauncher))
        t.reassign(space, to: "window.left-half")
        XCTAssertEqual(t.owner(of: space), HotkeyID.openLauncher)
    }

    func testClearLauncherThrows() {
        var t = HotkeyTable.defaults
        XCTAssertThrowsError(try t.clear(HotkeyID.openLauncher)); XCTAssertNoThrow(try t.clear("window.left-half"))
    }

    func testInvalidCombo() {
        var t = HotkeyTable.defaults
        XCTAssertEqual(t.assign(KeyCombo(keyCode: 9, modifiers: []), to: "x"), .invalid)
    }

    func testSeedAddsDefaultsOnce() {
        var t = HotkeyTable.defaults
        let seeded = t.seed(["window.left-half": left], alreadySeeded: [])
        XCTAssertEqual(seeded, ["window.left-half"]); XCTAssertEqual(t.combo(for: "window.left-half"), left)
        // The user removes it; a later launch must not bring it back.
        try? t.clear("window.left-half")
        XCTAssertEqual(t.seed(["window.left-half": left], alreadySeeded: seeded), [])
        XCTAssertNil(t.combo(for: "window.left-half"))
    }

    func testSeedNeverTakesAKeyInUseOrReplacesAUsersChoice() {
        var t = HotkeyTable.defaults
        _ = t.assign(left, to: "util.settings")                     // the user already uses ⌃⌥←
        let other = KeyCombo(keyCode: 124, modifiers: [.control, .option])
        _ = t.assign(other, to: "window.maximize")                  // and chose their own key for maximize
        let seeded = t.seed(["window.left-half": left, "window.maximize": KeyCombo(keyCode: 36, modifiers: [.control, .option])], alreadySeeded: [])
        XCTAssertEqual(seeded, ["window.left-half", "window.maximize"])   // both count as handled
        XCTAssertEqual(t.owner(of: left), "util.settings"); XCTAssertNil(t.combo(for: "window.left-half"))
        XCTAssertEqual(t.combo(for: "window.maximize"), other)
    }

    func testDecodingDropsDuplicatesAndRestoresLauncher() throws {
        // A hand-edited file: two actions on one key, and no launcher shortcut.
        let json = #"{"bindings":{"a":{"keyCode":123,"modifiers":6},"b":{"keyCode":123,"modifiers":6}}}"#
        let t = try JSONDecoder().decode(HotkeyTable.self, from: Data(json.utf8))
        XCTAssertEqual(t.owner(of: KeyCombo(keyCode: 123, modifiers: KeyModifiers(rawValue: 6))), "a")
        XCTAssertNil(t.combo(for: "b"))
        XCTAssertEqual(t.combo(for: HotkeyID.openLauncher), space)
    }

    // MARK: Snippets

    func testRegistrableKeepsOnlyLiveBindings() {
        var table = HotkeyTable.defaults
        _ = table.assign(KeyCombo(keyCode: 0, modifiers: [.control, .option]), to: "snippet:a")
        _ = table.assign(KeyCombo(keyCode: 1, modifiers: [.control, .option]), to: "snippet:gone")
        _ = table.assign(KeyCombo(keyCode: 2, modifiers: [.control, .option]), to: "window.left-half")
        let out = table.registrable(live: [HotkeyID.openLauncher, "snippet:a", "window.left-half"])
        XCTAssertEqual(Set(out.bindings.keys), [HotkeyID.openLauncher, "snippet:a", "window.left-half"])
        XCTAssertNotNil(table.combo(for: "snippet:gone"))
    }

    func testRegistrableLetsGoOfASwitchedOffFeatureButKeepsItsKey() {
        var table = HotkeyTable.defaults
        _ = table.assign(KeyCombo(keyCode: 9, modifiers: [.option]), to: "clipboard.open")
        // The launcher itself switched off: not even its key is registered.
        XCTAssertTrue(table.registrable(live: []).bindings.isEmpty)
        XCTAssertEqual(table.combo(for: "clipboard.open"), KeyCombo(keyCode: 9, modifiers: [.option]))
    }
}
