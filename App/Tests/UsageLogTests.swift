import XCTest
@testable import ToolsmithKit

final class UsageLogTests: XCTestCase {
    func testRecentBeatsOldAndPersists() {
        let url = tempFile(); let now = Fixture.now
        let log = UsageLog(fileURL: url)
        log.record("a", at: now.addingTimeInterval(-30 * 86_400))
        log.record("b", at: now)
        XCTAssertGreaterThan(log.score("b", now: now), log.score("a", now: now))
        XCTAssertEqual(log.score("b", now: now), 1.0, accuracy: 0.001)
        XCTAssertEqual(log.score("b", now: now.addingTimeInterval(7 * 86_400)), 0.5, accuracy: 0.001)
        XCTAssertEqual(UsageLog(fileURL: url).recentIDs(limit: 5, now: now), ["b", "a"])
    }

    func testCorruptFileStartsEmpty() throws {
        let url = tempFile(); try Data("not json".utf8).write(to: url)
        XCTAssertEqual(UsageLog(fileURL: url).recentIDs(limit: 5, now: Date()), [])
    }

    func testUnknownIDScoresZero() {
        XCTAssertEqual(UsageLog(fileURL: tempFile()).score("nope", now: Fixture.now), 0)
    }

    // MARK: Snippets

    func testRemoveForgetsAndPersists() {
        let url = tempFile(); let log = UsageLog(fileURL: url)
        log.record("snippet:a", at: Fixture.now); log.record("app:slack", at: Fixture.now); log.remove("snippet:a")
        XCTAssertEqual(UsageLog(fileURL: url).recentIDs(limit: 10, now: Fixture.now), ["app:slack"])
    }
}
