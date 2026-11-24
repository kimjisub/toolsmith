import XCTest
@testable import ToolsmithKit

final class HotkeyCatalogTests: XCTestCase {
    let space = KeyCombo(keyCode: 49, modifiers: [.command])
    let settings = HotkeyAction(id: "util.settings", title: "설정 열기", group: "앱", detail: nil)

    func testFilter() {
        let a = [HotkeyCatalog.launcher, settings]
        XCTAssertEqual(HotkeyCatalog.filter(a, query: "ㅅㅈ").map(\.id), ["util.settings"])
        XCTAssertEqual(HotkeyCatalog.filter(a, query: "").count, 2)
        XCTAssertEqual(HotkeyCatalog.filter(a, query: "  ").count, 2)
    }

    func testNotice() {
        XCTAssertEqual(HotkeyCatalog.notice(for: space, id: "x", system: [space], failed: [:]), .systemShortcut)
        XCTAssertEqual(HotkeyCatalog.notice(for: space, id: "x", system: [], failed: ["x": space]), .registrationFailed)
        XCTAssertNil(HotkeyCatalog.notice(for: space, id: "x", system: [], failed: ["y": space]))
    }

    func testActionsPutLauncherFirstThenCommandsWithHotkeyIDs() {
        let log = RunLog()
        let commands = [
            Command(id: "util.settings", title: "설정 열기", subtitle: nil, keywords: [], section: CommandSection(id: "util", title: "앱", order: 20),
                    icon: .symbol("gearshape"), hotkeyID: "util.settings", run: {}),
            Fixture.command("app:slack", "Slack", Fixture.apps, log: log),
        ]
        XCTAssertEqual(HotkeyCatalog.actions(from: commands), [HotkeyCatalog.launcher, settings])
    }

    func testGroupedKeepsOrder() {
        let window = HotkeyAction(id: "w", title: "왼쪽 절반", group: "화면 나누기", detail: nil)
        let grouped = HotkeyCatalog.grouped([settings, window, HotkeyAction(id: "q", title: "x", group: "앱", detail: nil)])
        XCTAssertEqual(grouped.map(\.group), ["앱", "화면 나누기"])
        XCTAssertEqual(grouped[0].actions.map(\.id), ["util.settings", "q"])
    }
}
