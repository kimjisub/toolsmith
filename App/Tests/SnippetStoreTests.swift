import XCTest
@testable import ToolsmithKit

final class SnippetStoreTests: XCTestCase {
    func testAddPersistsAndReloadsInCreationOrder() {
        let url = tempFile("snippets.json")
        let store = SnippetStore(fileURL: url, now: { Fixture.now })
        let a = store.add(name: "인사", body: "안녕하세요 {이름}님"); _ = store.add(name: "마무리", body: "감사합니다")
        XCTAssertEqual(a?.commandID, "snippet:\(a!.id.uuidString)")
        XCTAssertEqual(SnippetStore(fileURL: url).snippets.map(\.name), ["인사", "마무리"])
    }
    func testInvalidIsNotSaved() {
        let store = SnippetStore(fileURL: tempFile("snippets.json"))
        XCTAssertNil(store.add(name: "  ", body: "내용")); XCTAssertNil(store.add(name: "이름", body: "\n"))
        let a = store.add(name: "가", body: "나")!
        XCTAssertFalse(store.update(a.id, name: "", body: "나")); XCTAssertEqual(store.snippet(a.id)?.name, "가")
    }
    func testUpdateChangesUpdatedAtAndRemoveDeletes() {
        var clock = Fixture.now
        let url = tempFile("snippets.json"); let store = SnippetStore(fileURL: url, now: { clock })
        let a = store.add(name: "가", body: "나")!
        clock = Fixture.now.addingTimeInterval(60)
        XCTAssertTrue(store.update(a.id, name: "가2", body: "나2"))
        XCTAssertEqual(store.snippet(a.id)?.updatedAt, clock); XCTAssertEqual(store.snippet(a.id)?.createdAt, Fixture.now)
        store.remove(a.id); XCTAssertTrue(SnippetStore(fileURL: url).snippets.isEmpty)
    }
    func testBrokenFileIsKeptAside() throws {
        let url = tempFile("snippets.json"); try Data("{oops".utf8).write(to: url)
        let store = SnippetStore(fileURL: url)
        XCTAssertTrue(store.loadFailed); XCTAssertTrue(store.snippets.isEmpty)
        let aside = url.deletingLastPathComponent().appendingPathComponent("snippets.broken.json")
        XCTAssertEqual(try String(contentsOf: aside, encoding: .utf8), "{oops")
        _ = store.add(name: "가", body: "나")   // 새 파일에 쓴다. 옆에 둔 파일은 그대로다.
        XCTAssertEqual(try String(contentsOf: aside, encoding: .utf8), "{oops")
    }
    func testUnreadableFileIsKeptAsideToo() throws {
        let url = tempFile("snippets.json"); try Data("secret".utf8).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: url.path)
        let store = SnippetStore(fileURL: url)
        XCTAssertTrue(store.loadFailed)
        let aside = url.deletingLastPathComponent().appendingPathComponent("snippets.broken.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: aside.path))
        XCTAssertNotNil(store.add(name: "가", body: "나"))   // 원본을 옆으로 옮긴 뒤라 새 파일에 쓴다
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: aside.path)
        XCTAssertEqual(try String(contentsOf: aside, encoding: .utf8), "secret")
    }
    func testNothingIsWrittenWhenTheUnreadFileCannotBeMovedAside() throws {
        let url = tempFile("snippets.json"); try Data("{oops".utf8).write(to: url)
        let directory = url.deletingLastPathComponent()
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: directory.path)   // 읽기만 되는 폴더
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path) }
        let store = SnippetStore(fileURL: url)
        XCTAssertTrue(store.loadFailed); XCTAssertNil(store.add(name: "가", body: "나"))
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "{oops")
    }
    func testMissingFileIsNotAFailure() { XCTAssertFalse(SnippetStore(fileURL: tempFile("snippets.json")).loadFailed) }
    func testLoadDropsDuplicatesAndInvalid() throws {
        let url = tempFile("snippets.json")
        let id = "11111111-1111-1111-1111-111111111111", date = "2026-11-20T00:00:00Z"
        func item(_ id: String, _ name: String) -> String { #"{"id":"\#(id)","name":"\#(name)","body":"b","createdAt":"\#(date)","updatedAt":"\#(date)"}"# }
        try Data(#"{"schemaVersion":1,"snippets":[\#(item(id, "가")),\#(item(id, "중복")),\#(item("22222222-2222-2222-2222-222222222222", " "))]}"#.utf8).write(to: url)
        let store = SnippetStore(fileURL: url)
        XCTAssertFalse(store.loadFailed); XCTAssertEqual(store.snippets.map(\.name), ["가"])
    }
    func testFirstLine() {
        let store = SnippetStore(fileURL: tempFile("snippets.json"))
        XCTAssertEqual(store.add(name: "가", body: "\n  첫 줄  \n둘째")?.firstLine, "첫 줄")
    }
}
