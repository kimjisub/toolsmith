import XCTest
@testable import ToolsmithKit

final class LauncherEngineTests: XCTestCase {
    var usage: UsageLog!
    var engine: LauncherEngine!
    let now = Fixture.now

    override func setUp() {
        usage = UsageLog(fileURL: tempFile())
        engine = LauncherEngine(sources: [StubSource(list: Fixture.commands(log: RunLog()))], usage: usage, now: { Fixture.now })
        engine.reload()
    }

    func testGroupsBySectionInOrder() {
        let r = engine.results(for: "ㅇ")
        XCTAssertEqual(r.map(\.section.title), ["화면 나누기"])
        XCTAssertEqual(r[0].commandIDs, ["window.left-half", "window.left-third"])
    }

    func testBetterMatchKindFirstThenUsage() {
        usage.record("app:safari", at: now)
        XCTAssertEqual(engine.results(for: "s").first?.commandIDs, ["app:safari", "app:slack"])
    }

    func testKeywordsMatch() {
        XCTAssertEqual(engine.results(for: "슬").first?.commandIDs, ["app:slack"])
    }

    func testEmptyQueryShowsRecent() {
        usage.record("app:slack", at: now)
        XCTAssertEqual(engine.results(for: ""), [ResultSection(section: LauncherEngine.recentSection, commandIDs: ["app:slack"])])
    }

    func testEmptyQueryWithNoUsageIsEmpty() { XCTAssertEqual(engine.results(for: ""), []) }

    func testRecentSkipsCommandsThatNoLongerExist() {
        usage.record("app:gone", at: now); usage.record("app:slack", at: now.addingTimeInterval(-60))
        XCTAssertEqual(engine.results(for: "").first?.commandIDs, ["app:slack"])
    }

    func testFindsCommandByHotkeyID() {
        let log = RunLog()
        let settings = Command(id: "util.settings", title: "설정 열기", subtitle: nil, keywords: [], section: Fixture.apps,
                               icon: .symbol("gearshape"), hotkeyID: "util.settings", run: { log.ids.append("util.settings") })
        let e = LauncherEngine(sources: [StubSource(list: [settings] + Fixture.commands(log: log))], usage: usage); e.reload()
        XCTAssertEqual(e.command(hotkeyID: "util.settings")?.id, "util.settings")
        XCTAssertNil(e.command(hotkeyID: "app:slack"))
        XCTAssertEqual(e.hotkeyCommands().map(\.id), ["util.settings"])
    }

    func testTitleMatchBeatsKeywordMatch() {
        // 단축어 is found by its English name "Shortcuts", but an app actually called S… comes first.
        let log = RunLog()
        let list = [
            Fixture.command("app:shortcuts", "단축어", Fixture.apps, keywords: ["Shortcuts"], log: log),
            Fixture.command("app:safari", "Safari", Fixture.apps, log: log),
        ]
        let e = LauncherEngine(sources: [StubSource(list: list)], usage: usage, now: { Fixture.now }); e.reload()
        XCTAssertEqual(e.results(for: "s").first?.commandIDs, ["app:safari", "app:shortcuts"])
    }

    func testEmptyQueryShowsExtraSectionsAfterRecent() {
        // 「방금 복사한 것」: a feature can add sections to the empty launcher.
        let clips = CommandSection(id: "clip-recent", title: "방금 복사한 것", order: 1)
        engine.emptyStateExtra = { [ResultSection(section: clips, commandIDs: ["app:safari", "app:gone"])] }
        usage.record("app:slack", at: now)
        XCTAssertEqual(engine.results(for: ""), [
            ResultSection(section: LauncherEngine.recentSection, commandIDs: ["app:slack"]),
            ResultSection(section: clips, commandIDs: ["app:safari"]),          // unknown ids are dropped
        ])
        XCTAssertEqual(engine.results(for: "saf").map(\.section.title), ["앱"])   // only when the query is empty
    }

    func testPerSectionLimit() {
        let log = RunLog()
        let many = (0..<20).map { Fixture.command("app:\($0)", "Tool \($0)", Fixture.apps, log: log) }
        let e = LauncherEngine(sources: [StubSource(list: many)], usage: usage, now: { Fixture.now }); e.reload()
        XCTAssertEqual(e.results(for: "tool").first?.commandIDs.count, LauncherEngine.perSectionLimit)
    }

    func testSectionWithTheBestMatchComesFirst() {
        let log = RunLog()
        let windows = CommandSection(id: "windows", title: "화면 나누기", order: 0)
        let center = Command(id: "window.center", title: "가운데 3분의 1", subtitle: nil, keywords: ["center", "third"], section: windows,
                             icon: .symbol("rectangle"), hotkeyID: nil, run: {})
        let terminal = Fixture.command("app:terminal", "Terminal", Fixture.apps, log: log)
        let e = LauncherEngine(sources: [StubSource(list: [center, terminal])], usage: usage, now: { Fixture.now }); e.reload()
        // "te" sits in the middle of the keyword "center": that does not count.
        XCTAssertEqual(e.results(for: "te").map(\.commandIDs), [["app:terminal"]])
        // A title hit outranks a keyword hit, whatever the sections' fixed order.
        XCTAssertEqual(e.results(for: "t").map(\.commandIDs), [["app:terminal"], ["window.center"]])
        // The window command still leads when it is the better match.
        XCTAssertEqual(e.results(for: "가운데").first?.commandIDs, ["window.center"])
    }
}
