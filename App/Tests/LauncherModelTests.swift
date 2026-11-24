import XCTest
@testable import ToolsmithKit

@MainActor final class LauncherModelTests: XCTestCase {
    var usage: UsageLog!
    var model: LauncherModel!
    var log: RunLog!
    let now = Fixture.now
    var ran: [String] { log.ids }

    override func setUp() async throws {
        log = RunLog()
        usage = UsageLog(fileURL: tempFile())
        let engine = LauncherEngine(sources: [StubSource(list: Fixture.commands(log: log))], usage: usage, now: { Fixture.now })
        engine.reload()
        model = LauncherModel(engine: engine, usage: usage, now: { Fixture.now })
    }

    func testTypingSelectsFirstResult() { model.query = "왼"; XCTAssertEqual(model.selectedID, "window.left-half") }

    func testReturnThatCommitsTheSyllableRunsTheWholeWord() {
        // The field reports the syllable while it is composed, then the same text once Return commits it.
        model.query = "왼"; model.query = "왼"
        XCTAssertEqual(model.submit(), .ran("window.left-half")); XCTAssertEqual(ran, ["window.left-half"])
    }

    func testNoResultsSelectsNothing() {
        model.query = "zzzz"
        XCTAssertNil(model.selectedID); XCTAssertFalse(model.activateSelected()); XCTAssertTrue(ran.isEmpty)
    }

    func testMoveStopsAtEnds() {
        model.query = "왼"; model.moveSelection(by: -1); XCTAssertEqual(model.selectedID, "window.left-half")
        model.moveSelection(by: 1); XCTAssertEqual(model.selectedID, "window.left-third")
        model.moveSelection(by: 5); XCTAssertEqual(model.selectedID, LauncherModel.aiRowID)   // the AI row is the last stop
    }

    func testActivateRunsAndRecordsUsage() {
        model.query = "sla"; XCTAssertTrue(model.activateSelected())
        XCTAssertEqual(ran, ["app:slack"]); XCTAssertGreaterThan(usage.score("app:slack", now: now), 0)
    }

    func testNumberActivatesVisibleRow() {
        model.query = "왼"; XCTAssertTrue(model.activate(number: 2)); XCTAssertEqual(ran, ["window.left-third"])
        XCTAssertFalse(model.activate(number: 9)); XCTAssertFalse(model.activate(number: 0))
    }

    func testResetClearsQueryAndShowsRecent() {
        model.query = "sla"; model.activateSelected(); model.reset()
        XCTAssertEqual(model.query, ""); XCTAssertEqual(model.visibleIDs, ["app:slack"]); XCTAssertEqual(model.selectedID, "app:slack")
    }

    func testRefreshKeepsSelectionWhenItIsStillVisible() {
        // The app list finishes rescanning while the user has already moved down the list.
        model.query = "왼"; model.moveSelection(by: 1)
        model.refresh()
        XCTAssertEqual(model.selectedID, "window.left-third")
    }

    func testTypingStillResetsSelectionToFirst() {
        model.query = "왼"; model.moveSelection(by: 1); model.query = "왼쪽"
        XCTAssertEqual(model.selectedID, "window.left-half")
    }

    func testCommandsCanOptOutOfTheRecentList() {
        // A clipboard entry run from the launcher must not come back as a "recent command".
        let log = RunLog(); let usage = UsageLog(fileURL: tempFile())
        let clip = Command(id: "clip:1", title: "복사한 글", subtitle: nil, keywords: [], section: Fixture.apps, icon: .symbol("doc"),
                           hotkeyID: nil, tracksUsage: false, run: { log.ids.append("clip:1") })
        let engine = LauncherEngine(sources: [StubSource(list: [clip])], usage: usage, now: { Fixture.now }); engine.reload()
        let model = LauncherModel(engine: engine, usage: usage, now: { Fixture.now })
        XCTAssertTrue(model.activate(id: "clip:1")); XCTAssertEqual(log.ids, ["clip:1"])
        XCTAssertEqual(usage.score("clip:1", now: Fixture.now), 0)
    }

    func testActivateByID() {
        model.query = "왼"; XCTAssertTrue(model.activate(id: "window.left-third")); XCTAssertEqual(ran, ["window.left-third"])
        XCTAssertFalse(model.activate(id: "nope"))
    }

    // MARK: Snippets

    private func fill(_ body: String = "{이름}님", returnsToList: Bool = true) -> SnippetFill {
        SnippetFill(snippet: Snippet(id: UUID(), name: "인사", body: body, createdAt: now, updatedAt: now), returnsToList: returnsToList)
    }
    func testFillKeepsQueryAndReturnsToList() {
        model.query = "왼"; model.moveSelection(by: 1)
        model.beginFill(fill()); XCTAssertEqual(model.mode, .fill); XCTAssertFalse(model.showsAIRow)
        XCTAssertFalse(model.activate(number: 1)); XCTAssertEqual(model.submit(), .nothing); XCTAssertTrue(ran.isEmpty)
        XCTAssertEqual(model.cancelFill(), .backToList)
        XCTAssertEqual(model.mode, .commands); XCTAssertEqual(model.query, "왼"); XCTAssertEqual(model.selectedID, "window.left-third")
    }
    func testFillFromHotkeyCloses() {
        model.beginFill(fill(returnsToList: false)); XCTAssertEqual(model.cancelFill(), .close); XCTAssertNil(model.fill)
    }
    func testSubmitFillRecordsUsageOnlyThen() {
        let f = fill(); model.beginFill(f)
        XCTAssertEqual(usage.score(f.commandID, now: now), 0)
        model.setFillValue("가", at: 0)
        XCTAssertEqual(model.submitFill(), "가님"); XCTAssertGreaterThan(usage.score(f.commandID, now: now), 0)
        XCTAssertNil(model.fill); XCTAssertNil(model.submitFill())
    }
    func testCancelledFillLeavesNoUsage() {
        let f = fill(); model.beginFill(f); model.cancelFill(); XCTAssertEqual(usage.score(f.commandID, now: now), 0)
    }
    func testBeginFillReplacesCurrentFill() {
        model.beginFill(fill()); model.setFillValue("가", at: 0)
        model.beginFill(fill("{회사}", returnsToList: false))
        XCTAssertEqual(model.fill?.values, [""]); XCTAssertEqual(model.cancelFill(), .close)
    }
    func testRefreshDuringFillKeepsValidSelection() {
        model.query = "왼"; model.moveSelection(by: 1); model.beginFill(fill())
        model.refresh(); XCTAssertEqual(model.mode, .fill)
        model.cancelFill(); XCTAssertEqual(model.selectedID, "window.left-third")
    }
    func testResetLeavesFill() { model.beginFill(fill()); model.reset(); XCTAssertEqual(model.mode, .commands); XCTAssertNil(model.fill) }

    // MARK: Snippet search

    private func snippetModel() -> (LauncherModel, Snippet, Snippet) {
        let store = SnippetStore(fileURL: tempFile("snippets.json"))
        let a = store.add(name: "인사", body: "{이름}님")!, b = store.add(name: "마무리", body: "감사합니다")!
        let engine = LauncherEngine(sources: [StubSource(list: Fixture.commands(log: log)), SnippetCommandSource(store: store)], usage: usage, now: { Fixture.now })
        engine.reload()
        return (LauncherModel(engine: engine, usage: usage, now: { Fixture.now }), a, b)
    }
    func testSnippetSearchShowsOnlySnippets() {
        let (model, a, b) = snippetModel()
        model.query = "왼"
        model.enterSnippetSearch(returnsToList: true)
        XCTAssertEqual(model.mode, .snippets); XCTAssertEqual(model.query, "")
        XCTAssertEqual(model.visibleIDs, [a.commandID, b.commandID, "snippets.new"]); XCTAssertEqual(model.selectedID, a.commandID)
        model.query = "마무"
        XCTAssertEqual(model.visibleIDs, [b.commandID]); XCTAssertFalse(model.showsAIRow)
        model.query = "왼"
        XCTAssertEqual(model.visibleIDs, [])
        // A leading "." is text here, not the way to the AI.
        model.query = ""; model.query = "."
        XCTAssertEqual(model.mode, .snippets); XCTAssertEqual(model.query, ".")
    }
    func testLeavingSnippetSearch() {
        let (model, _, _) = snippetModel()
        model.enterSnippetSearch(returnsToList: true); model.query = "마무"
        XCTAssertTrue(model.snippetSearchReturnsToList)
        XCTAssertEqual(model.exitSnippetSearch(), .backToList)
        XCTAssertEqual(model.mode, .commands); XCTAssertEqual(model.query, "")
        model.enterSnippetSearch(returnsToList: false)
        XCTAssertEqual(model.exitSnippetSearch(), .close); XCTAssertEqual(model.mode, .commands)
        XCTAssertEqual(model.exitSnippetSearch(), .close) // not searching snippets: nothing to go back to
    }
    func testFillFromSnippetSearchGoesBackThere() {
        let (model, a, _) = snippetModel()
        model.enterSnippetSearch(returnsToList: false); model.query = "인"
        model.beginFill(SnippetFill(snippet: a, returnsToList: true))
        XCTAssertEqual(model.mode, .fill)
        model.refresh(); XCTAssertEqual(model.visibleIDs, [a.commandID]) // still only snippets underneath
        XCTAssertEqual(model.cancelFill(), .backToList)
        XCTAssertEqual(model.mode, .snippets); XCTAssertEqual(model.query, "인"); XCTAssertEqual(model.visibleIDs, [a.commandID])
        XCTAssertFalse(model.snippetSearchReturnsToList)
        model.beginFill(SnippetFill(snippet: a, returnsToList: true))
        XCTAssertNotNil(model.submitFill()); XCTAssertEqual(model.mode, .commands)
    }
    func testResetLeavesSnippetSearch() {
        let (model, _, _) = snippetModel()
        model.enterSnippetSearch(returnsToList: false); model.query = "인"; model.reset()
        XCTAssertEqual(model.mode, .commands); XCTAssertEqual(model.query, "")
        XCTAssertFalse(model.visibleIDs.contains("snippets.new"))
    }
}
