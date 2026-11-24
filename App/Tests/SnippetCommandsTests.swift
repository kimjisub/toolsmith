import XCTest
@testable import ToolsmithKit

@MainActor final class SnippetCommandsTests: XCTestCase {
    func testCommandsShape() {
        let store = SnippetStore(fileURL: tempFile("snippets.json"))
        let plain = store.add(name: "마무리", body: "감사합니다")!, asking = store.add(name: "인사", body: "\n{이름}님\n둘\n셋\n넷\n다섯\n여섯")!
        let source = SnippetCommandSource(store: store)
        var inserted: [String] = [], filled: [String] = [], made = 0
        source.onInsert = { snippet, template in inserted.append(snippet.name); XCTAssertTrue(template.variables.isEmpty) }
        source.onFill = { filled.append($0.name) }; source.onNew = { made += 1 }
        let commands = Array(source.commands().dropFirst())
        XCTAssertEqual(commands.map(\.id), [plain.commandID, asking.commandID, "snippets.new"])
        XCTAssertEqual(commands[0].hotkeyID, plain.commandID); XCTAssertEqual(commands[0].subtitle, "감사합니다")
        XCTAssertFalse(commands[0].keepsLauncherOpen); XCTAssertTrue(commands[0].tracksUsage)
        XCTAssertTrue(commands[1].keepsLauncherOpen); XCTAssertFalse(commands[1].tracksUsage)
        XCTAssertEqual(commands[1].keywords, ["{이름}님", "둘", "셋", "넷", "다섯"])
        XCTAssertNil(commands[2].hotkeyID)
        commands.forEach { $0.run() }
        XCTAssertEqual(inserted, ["마무리"]); XCTAssertEqual(filled, ["인사"]); XCTAssertEqual(made, 1)
    }
    func testFoundByNameAndBody() {
        let store = SnippetStore(fileURL: tempFile("snippets.json")); let a = store.add(name: "인사", body: "포지션 건으로 연락드립니다")!
        let engine = LauncherEngine(sources: [SnippetCommandSource(store: store)], usage: UsageLog(fileURL: tempFile()), now: { Fixture.now })
        engine.reload()
        XCTAssertEqual(engine.results(for: "인사").first?.commandIDs, [a.commandID])
        XCTAssertEqual(engine.results(for: "연락드").first?.commandIDs, [a.commandID])
    }
    func testSearchCommand() {
        let source = SnippetCommandSource(store: SnippetStore(fileURL: tempFile("snippets.json")))
        var searched = 0; source.onSearch = { searched += 1 }
        let search = source.commands()[0]
        XCTAssertEqual(search.id, "snippets.search"); XCTAssertEqual(search.hotkeyID, "snippets.search"); XCTAssertTrue(Set([search.title] + search.keywords).isSuperset(of: ["Search Snippets", "스니펫 검색"]))
        XCTAssertTrue(search.keepsLauncherOpen)
        search.run(); XCTAssertEqual(searched, 1)
    }
    func testResultsWithinTheSnippetSection() {
        let store = SnippetStore(fileURL: tempFile("snippets.json"))
        let a = store.add(name: "인사", body: "포지션 건으로 연락드립니다")!, b = store.add(name: "마무리", body: "감사합니다")!
        let usage = UsageLog(fileURL: tempFile())
        let other = Command(id: "app:1", title: "인사 관리", subtitle: nil, keywords: [], section: Fixture.apps, icon: .symbol("doc"), hotkeyID: nil, run: {})
        let engine = LauncherEngine(sources: [StubSource(list: [other]), SnippetCommandSource(store: store)], usage: usage, now: { Fixture.now })
        engine.reload()
        usage.record(b.commandID, at: Fixture.now); usage.record(SnippetCommandSource.newID, at: Fixture.now)
        func ids(_ query: String) -> [[String]] {
            engine.results(for: query, in: SnippetCommandSource.section, excluding: [SnippetCommandSource.searchID], trailing: [SnippetCommandSource.newID]).map(\.commandIDs)
        }
        // Nothing typed: every snippet, the most used first, 「스니펫 만들기」 last however much it is used.
        XCTAssertEqual(ids(""), [[b.commandID, a.commandID, "snippets.new"]])
        XCTAssertEqual(ids("인사"), [[a.commandID]])
        XCTAssertEqual(ids("감사"), [[b.commandID]])
        XCTAssertEqual(ids("스니펫"), [["snippets.new"]])
        XCTAssertEqual(ids("없는말"), [])
    }
    func testScopedResultsAreNotCutAtTheSectionLimit() {
        let store = SnippetStore(fileURL: tempFile("snippets.json"))
        for index in 0..<12 { _ = store.add(name: "멘트 \(index)", body: "내용") }
        let engine = LauncherEngine(sources: [SnippetCommandSource(store: store)], usage: UsageLog(fileURL: tempFile()), now: { Fixture.now })
        engine.reload()
        XCTAssertEqual(engine.results(for: "멘트").first?.commandIDs.count, LauncherEngine.perSectionLimit)
        // 「스니펫 검색」 and 「스니펫 만들기」 are found by "멘트" too; left out, the twelve snippets remain.
        let helpers: Set = [SnippetCommandSource.searchID, SnippetCommandSource.newID]
        XCTAssertEqual(engine.results(for: "멘트", in: SnippetCommandSource.section, excluding: helpers, trailing: []).first?.commandIDs.count, 12)
    }
}
