import XCTest
@testable import ToolsmithKit

final class ClipStoreTests: XCTestCase {
    var dir: URL!
    var store: ClipStore!
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    override func setUpWithError() throws {
        dir = tempFile("clipboard")
        store = try ClipStore(directory: dir)
    }

    private func text(_ string: String, from app: String? = "Slack") -> ClipDraft {
        ClipDraft(kind: ClipboardPolicy.kind(forText: string), text: string, data: nil, fileURLs: [],
                  sourceBundleID: app.map { "com.test.\($0)" }, sourceName: app, width: nil, height: nil)
    }

    private func image(_ bytes: [UInt8]) -> ClipDraft {
        ClipDraft(kind: .image, text: nil, data: Data(bytes), fileURLs: [], sourceBundleID: nil, sourceName: nil, width: 1280, height: 720)
    }

    private func all(_ query: String = "", kind: ClipKind? = nil, pinnedOnly: Bool = false) -> [ClipItem] {
        store.items(query: query, kind: kind, pinnedOnly: pinnedOnly, limit: 100, offset: 0)
    }

    func testNewestFirst() throws {
        try store.record(text("첫째"), at: t0)
        try store.record(text("둘째"), at: t0.addingTimeInterval(10))
        XCTAssertEqual(all().map(\.text), ["둘째", "첫째"])
        XCTAssertEqual(all()[0].sourceName, "Slack")
    }

    func testSameContentMovesToFrontInsteadOfDuplicating() throws {
        let first = try store.record(text("가"), at: t0)
        try store.record(text("나"), at: t0.addingTimeInterval(1))
        let again = try store.record(text("가"), at: t0.addingTimeInterval(2))
        XCTAssertEqual(again.id, first.id)
        XCTAssertEqual(all().map(\.text), ["가", "나"])
        XCTAssertEqual(all()[0].copiedAt, t0.addingTimeInterval(2))
    }

    func testSearchMatchesComposingHangulAndSourceApp() throws {
        try store.record(text("내일 오후 3시에 통화 가능하실까요?"), at: t0)
        try store.record(text("회의실 예약", from: "Notes"), at: t0.addingTimeInterval(1))
        XCTAssertEqual(all("통화").count, 1)
        XCTAssertEqual(all("토").count, 1)                  // 「통」 을 치는 중
        XCTAssertEqual(all("SLACK").map(\.sourceName), ["Slack"])
        XCTAssertEqual(all("없는말").count, 0)
        XCTAssertEqual(all("  ").count, 2)
    }

    func testSearchTreatsWildcardsAsPlainText() throws {
        try store.record(text("100% 완료"), at: t0)
        try store.record(text("진행 중"), at: t0.addingTimeInterval(1))
        XCTAssertEqual(all("%").map(\.text), ["100% 완료"])
        XCTAssertEqual(all("_").count, 0)
    }

    func testKindFilterAndLinkDetection() throws {
        try store.record(text("https://meet.google.com/abc-defg-hij"), at: t0)
        try store.record(text("메모"), at: t0.addingTimeInterval(1))
        try store.record(image([1, 2, 3]), at: t0.addingTimeInterval(2))
        XCTAssertEqual(all(kind: .link).count, 1)
        XCTAssertEqual(all(kind: .text).map(\.text), ["메모"])
        XCTAssertEqual(all(kind: .image).first?.width, 1280)
    }

    func testPin() throws {
        let item = try store.record(text("자주 쓰는 문구"), at: t0)
        try store.record(text("다른 것"), at: t0.addingTimeInterval(1))
        store.setPinned(item.id, true)
        XCTAssertEqual(all(pinnedOnly: true).map(\.text), ["자주 쓰는 문구"])
        store.setPinned(item.id, false)
        XCTAssertEqual(all(pinnedOnly: true).count, 0)
    }

    func testDeleteAndRestore() throws {
        let item = try store.record(text("지울 것"), at: t0)
        try store.record(text("남을 것"), at: t0.addingTimeInterval(1))
        let removed = store.delete(item.id)
        XCTAssertEqual(removed?.text, "지울 것"); XCTAssertEqual(all().map(\.text), ["남을 것"])
        store.restore(removed!)
        XCTAssertEqual(all().map(\.text), ["남을 것", "지울 것"])   // back where it was in time
        XCTAssertNil(store.delete(9_999))
    }

    func testImageBlobSurvivesDeleteUntilSweepAndComesBackOnRestore() throws {
        let item = try store.record(image([9, 9, 9, 9]), at: t0)
        let url = try XCTUnwrap(store.blobURL(for: item))
        XCTAssertEqual(try Data(contentsOf: url), Data([9, 9, 9, 9]))
        let removed = try XCTUnwrap(store.delete(item.id))
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))     // kept for undo
        store.restore(removed)
        XCTAssertEqual(store.sweepBlobs(), 0)
        _ = store.delete(item.id)
        XCTAssertEqual(store.sweepBlobs(), 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    func testPurgeRemovesOldUnpinnedOnly() throws {
        let old = try store.record(text("오래된 것"), at: t0.addingTimeInterval(-100 * 86_400))
        let kept = try store.record(text("오래됐지만 고정"), at: t0.addingTimeInterval(-100 * 86_400))
        try store.record(text("최근"), at: t0)
        store.setPinned(kept.id, true)
        XCTAssertEqual(store.purge(olderThan: t0.addingTimeInterval(-30 * 86_400)), 1)
        XCTAssertEqual(Set(all().map(\.text)), ["오래됐지만 고정", "최근"])
        XCTAssertNil(store.delete(old.id))
    }

    func testRetentionCutoff() {
        XCTAssertNil(ClipRetention.forever.cutoff(now: t0))
        XCTAssertEqual(ClipRetention.days30.cutoff(now: t0), t0.addingTimeInterval(-30 * 86_400))
        XCTAssertEqual(ClipRetention.days90.cutoff(now: t0), t0.addingTimeInterval(-90 * 86_400))
        XCTAssertEqual(ClipRetention.year.cutoff(now: t0), t0.addingTimeInterval(-365 * 86_400))
    }

    func testStatsAndClearAll() throws {
        try store.record(text("가나다"), at: t0)                           // 9 bytes of UTF-8
        let pinned = try store.record(image([1, 2, 3, 4, 5]), at: t0.addingTimeInterval(1))
        store.setPinned(pinned.id, true)
        XCTAssertEqual(store.stats().count, 2); XCTAssertEqual(store.stats().bytes, 14)
        store.clearAll(keepPinned: true)
        XCTAssertEqual(all().count, 1)
        store.clearAll(keepPinned: false)
        XCTAssertEqual(store.stats().count, 0)
        XCTAssertEqual(store.sweepBlobs(), 1)
    }

    func testPersistsAcrossReopen() throws {
        try store.record(text("남아야 함"), at: t0)
        store = nil
        XCTAssertEqual(try ClipStore(directory: dir).items(query: "", kind: nil, pinnedOnly: false, limit: 10, offset: 0).map(\.text), ["남아야 함"])
    }

    func testPaging() throws {
        for i in 0..<5 { try store.record(text("항목 \(i)"), at: t0.addingTimeInterval(Double(i))) }
        XCTAssertEqual(store.items(query: "", kind: nil, pinnedOnly: false, limit: 2, offset: 2).map(\.text), ["항목 2", "항목 1"])
    }

    func testTouchMovesToFront() throws {
        let a = try store.record(text("가"), at: t0)
        try store.record(text("나"), at: t0.addingTimeInterval(1))
        store.touch(a.id, at: t0.addingTimeInterval(5))
        XCTAssertEqual(all().map(\.text), ["가", "나"])
    }

    func testEmptyDraftIsRejected() {
        XCTAssertThrowsError(try store.record(text("   \n"), at: t0))
        XCTAssertThrowsError(try store.record(ClipDraft(kind: .image, text: nil, data: nil, fileURLs: [], sourceBundleID: nil, sourceName: nil, width: nil, height: nil), at: t0))
    }

    func testTextKeepsItsFormattingAsideWithoutCountingIt() throws {
        // The rich form (RTF) rides along for pasting; identity and size are the plain text.
        let rich = ClipDraft(kind: .text, text: "굵은 글", data: Data([1, 2, 3, 4, 5, 6]), fileURLs: [], sourceBundleID: nil, sourceName: nil, width: nil, height: nil)
        let item = try store.record(rich, at: t0)
        XCTAssertEqual(item.bytes, 10)
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(store.blobURL(for: item))), Data([1, 2, 3, 4, 5, 6]))
        XCTAssertEqual(try store.record(text("굵은 글"), at: t0.addingTimeInterval(1)).id, item.id)
    }

    func testFiles() throws {
        let draft = ClipDraft(kind: .file, text: nil, data: nil, fileURLs: ["/Users/x/통화 가능 시간.xlsx", "/Users/x/b.pdf"],
                              sourceBundleID: "com.apple.finder", sourceName: "Finder", width: nil, height: nil)
        let item = try store.record(draft, at: t0)
        XCTAssertEqual(item.fileURLs, ["/Users/x/통화 가능 시간.xlsx", "/Users/x/b.pdf"])
        XCTAssertEqual(all("통화").count, 1)
    }
}

final class ClipboardPolicyTests: XCTestCase {
    private func ok(_ types: [String], app: String? = "com.tinyspeck.slackmacgap", ignored: Set<String> = [], paused: Bool = false) -> Bool {
        ClipboardPolicy.shouldRecord(types: types, sourceBundleID: app, ignoredApps: ignored, paused: paused)
    }

    func testRecordsOrdinaryCopies() { XCTAssertTrue(ok(["public.utf8-plain-text"])) }

    func testSkipsConcealedAndTransient() {
        XCTAssertFalse(ok(["public.utf8-plain-text", "org.nspasteboard.ConcealedType"]))
        XCTAssertFalse(ok(["public.utf8-plain-text", "org.nspasteboard.TransientType"]))
        XCTAssertFalse(ok(["public.utf8-plain-text", "org.nspasteboard.AutoGeneratedType"]))
    }

    func testSkipsCopiesFromOtherDevices() {
        XCTAssertFalse(ok(["public.utf8-plain-text", "com.apple.is-remote-clipboard"], app: nil))
        XCTAssertFalse(ok(["public.png", "com.apple.is-remote-clipboard"]))
    }

    func testSkipsIgnoredAppsPausedAndOurOwnWrites() {
        XCTAssertFalse(ok(["public.utf8-plain-text"], app: "com.1password.1password", ignored: ["com.1password.1password"]))
        XCTAssertFalse(ok(["public.utf8-plain-text"], paused: true))
        XCTAssertFalse(ok(["public.utf8-plain-text", ClipboardPolicy.ownMarker]))
        XCTAssertTrue(ok(["public.utf8-plain-text"], app: nil, ignored: ["com.1password.1password"]))
    }

    func testDefaultIgnoredAppsCoverPasswordManagers() {
        XCTAssertTrue(ClipboardPolicy.defaultIgnoredApps.contains("com.1password.1password"))
        XCTAssertTrue(ClipboardPolicy.defaultIgnoredApps.contains("com.apple.keychainaccess"))
        XCTAssertTrue(ClipboardPolicy.defaultIgnoredApps.contains("com.apple.Passwords"))
    }

    func testLinkDetection() {
        XCTAssertEqual(ClipboardPolicy.kind(forText: "https://example.com/positions/12"), .link)
        XCTAssertEqual(ClipboardPolicy.kind(forText: "  http://example.com \n"), .link)
        XCTAssertEqual(ClipboardPolicy.kind(forText: "링크는 https://example.com 입니다"), .text)
        XCTAssertEqual(ClipboardPolicy.kind(forText: "https://"), .text)
        XCTAssertEqual(ClipboardPolicy.kind(forText: "메모"), .text)
    }
}

final class RelativeTimeTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    private func ago(_ seconds: TimeInterval) -> String { RelativeTime.text(from: now.addingTimeInterval(-seconds), now: now, locale: english) }

    func testSteps() {
        XCTAssertEqual(ago(5), "Just now")
        XCTAssertEqual(ago(59), "Just now")
        XCTAssertEqual(ago(60), "1 minute ago")
        XCTAssertEqual(ago(14 * 60), "14 minutes ago")
        XCTAssertEqual(ago(3_600), "1 hour ago")
        XCTAssertEqual(ago(23 * 3_600), "23 hours ago")
        XCTAssertEqual(ago(24 * 3_600), "1 day ago")
        XCTAssertEqual(ago(29 * 86_400), "29 days ago")
        XCTAssertEqual(ago(30 * 86_400), "1 month ago")
        XCTAssertEqual(ago(364 * 86_400), "12 months ago")
        XCTAssertEqual(ago(365 * 86_400), "1 year ago")
        XCTAssertEqual(ago(-30), "Just now")       // a clock that moved back
    }
}

final class ByteSizeTests: XCTestCase {
    func testText() {
        XCTAssertEqual(ByteSize.text(0, locale: english), "0 B")
        XCTAssertEqual(ByteSize.text(999, locale: english), "999 B")
        XCTAssertEqual(ByteSize.text(1_500, locale: english), "1.5 KB")
        XCTAssertEqual(ByteSize.text(2_000_000, locale: english), "2 MB")
        XCTAssertEqual(ByteSize.text(5_300_000_000, locale: english), "5.3 GB")
    }
}
