import XCTest
@testable import ToolsmithKit

final class ScreenTimeTests: XCTestCase {
    var store: ScreenTimeStore!
    var calendar: Calendar!

    override func setUpWithError() throws {
        calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
        store = try ScreenTimeStore(directory: tempFile("screentime"), calendar: calendar)
    }

    private func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
    }

    func testAccumulatesPerAppAndSortsByTime() {
        store.add(seconds: 600, bundleID: "com.slack", name: "Slack", at: date(13, 10))
        store.add(seconds: 300, bundleID: "com.chrome", name: "Chrome", at: date(13, 10, 30))
        store.add(seconds: 900, bundleID: "com.chrome", name: "Chrome", at: date(13, 14))
        let apps = store.apps(on: date(13, 23))
        XCTAssertEqual(apps.map(\.name), ["Chrome", "Slack"])
        XCTAssertEqual(apps.map(\.seconds), [1_200, 600])
        XCTAssertEqual(store.total(on: date(13, 1)), 1_800)
    }

    func testDaysAreSeparateAndFollowTheLocalCalendar() {
        store.add(seconds: 100, bundleID: "a", name: "A", at: date(12, 23, 59))
        store.add(seconds: 200, bundleID: "a", name: "A", at: date(13, 0, 1))
        XCTAssertEqual(store.total(on: date(12, 12)), 100)
        XCTAssertEqual(store.total(on: date(13, 12)), 200)
    }

    func testHourly() {
        store.add(seconds: 600, bundleID: "a", name: "A", at: date(13, 9, 10))
        store.add(seconds: 300, bundleID: "b", name: "B", at: date(13, 9, 50))
        store.add(seconds: 120, bundleID: "a", name: "A", at: date(13, 15))
        let hours = store.hourly(on: date(13, 0))
        XCTAssertEqual(hours.count, 24); XCTAssertEqual(hours[9], 900); XCTAssertEqual(hours[15], 120); XCTAssertEqual(hours[3], 0)
    }

    func testRecentDaysOldestFirstIncludingEmptyDays() {
        store.add(seconds: 100, bundleID: "a", name: "A", at: date(11, 10))
        store.add(seconds: 300, bundleID: "a", name: "A", at: date(13, 10))
        XCTAssertEqual(store.dailyTotals(endingOn: date(13, 12), days: 4), [0, 100, 0, 300])
    }

    func testClearAndReopen() throws {
        let dir = tempFile("st2")
        var s: ScreenTimeStore? = try ScreenTimeStore(directory: dir, calendar: calendar)
        s?.add(seconds: 60, bundleID: "a", name: "A", at: date(13, 10))
        s = nil
        let again = try ScreenTimeStore(directory: dir, calendar: calendar)
        XCTAssertEqual(again.total(on: date(13, 10)), 60)
        again.clearAll()
        XCTAssertEqual(again.total(on: date(13, 10)), 0)
    }

    func testIgnoresNonsense() {
        store.add(seconds: 0, bundleID: "a", name: "A", at: date(13, 10))
        store.add(seconds: -5, bundleID: "a", name: "A", at: date(13, 10))
        XCTAssertEqual(store.apps(on: date(13, 10)).count, 0)
    }

    private func counts(idle: Double = 10, locked: Bool = false, asleep: Bool = false, inCall: Bool = false, enabled: Bool = true) -> Bool {
        ActivityRule.shouldCount(idleSeconds: idle, screenLocked: locked, displayAsleep: asleep, inCall: inCall, enabled: enabled)
    }

    func testActivityRule() {
        XCTAssertTrue(counts())
        XCTAssertFalse(counts(idle: 301))    // walked away
        XCTAssertFalse(counts(locked: true))
        XCTAssertFalse(counts(asleep: true))
        XCTAssertFalse(counts(enabled: false))
    }

    func testACallCountsWithoutInput() {
        XCTAssertTrue(counts(idle: 3_600, inCall: true))      // an hour-long video meeting, hands off the keyboard
        XCTAssertFalse(counts(idle: 3_600, asleep: true, inCall: true))
        XCTAssertFalse(counts(idle: 3_600, locked: true, inCall: true))
        XCTAssertFalse(counts(idle: 3_600, inCall: true, enabled: false))
    }

    func testTheCallIsAskedOnlyWhenIdle() {
        var asked = 0
        func inCall() -> Bool { asked += 1; return true }
        _ = ActivityRule.shouldCount(idleSeconds: 10, screenLocked: false, displayAsleep: false, inCall: inCall(), enabled: true)
        XCTAssertEqual(asked, 0)
        _ = ActivityRule.shouldCount(idleSeconds: 301, screenLocked: false, displayAsleep: false, inCall: inCall(), enabled: true)
        XCTAssertEqual(asked, 1)
    }

    func testDurationText() {
        XCTAssertEqual(DurationText.text(20, locale: english), "Less than 1 min")
        XCTAssertEqual(DurationText.text(45 * 60, locale: english), "45 min")
        XCTAssertEqual(DurationText.text(3 * 3_600 + 12 * 60 + 40, locale: english), "3 hr, 12 min")
        XCTAssertEqual(DurationText.text(2 * 3_600, locale: english), "2 hr")
    }

    func testInsights() {
        let apps = [AppUsage(bundleID: "s", name: "Slack", seconds: 3_900), AppUsage(bundleID: "c", name: "Chrome", seconds: 2_100)]
        var hourly = [Double](repeating: 0, count: 24)
        hourly[14] = 3_000; hourly[10] = 1_800; hourly[9] = 1_200
        let lines = ScreenTimeInsights.lines(apps: apps, hourly: hourly, previousDays: [7_200, 3_600, 0, 5_400], locale: english)
        XCTAssertEqual(lines, [
            "10 min more than yesterday.",                              // 6000 vs 5400
            "10 min more than your recent average (1 hr, 30 min).",    // average of the days that had any use
            "You used Slack the most (1 hr, 5 min, 65%).",
            "Your busiest hour was 2\u{202F}PM.",
            "You started at 9\u{202F}AM.",
        ])
    }

    func testInsightsWithNothingToCompare() {
        XCTAssertEqual(ScreenTimeInsights.lines(apps: [], hourly: [Double](repeating: 0, count: 24), previousDays: [], locale: english), ["Nothing recorded yet."])
        let apps = [AppUsage(bundleID: "s", name: "Slack", seconds: 600)]
        var hourly = [Double](repeating: 0, count: 24); hourly[0] = 600
        let lines = ScreenTimeInsights.lines(apps: apps, hourly: hourly, previousDays: [0, 0], locale: english)
        XCTAssertEqual(lines.first, "You used Slack the most (10 min, 100%).")
        XCTAssertTrue(lines.contains("Your busiest hour was 12\u{202F}AM."))
    }

    func testInsightUsedLess() {
        let apps = [AppUsage(bundleID: "s", name: "Slack", seconds: 1_800)]
        var hourly = [Double](repeating: 0, count: 24); hourly[13] = 1_800
        XCTAssertEqual(ScreenTimeInsights.lines(apps: apps, hourly: hourly, previousDays: [3_600], locale: english).first, "30 min less than yesterday.")
    }

    func testInsightComparesWithTheSameTimeOfDay() {
        let apps = [AppUsage(bundleID: "s", name: "Slack", seconds: 1_800)]
        var hourly = [Double](repeating: 0, count: 24); hourly[9] = 1_800
        let lines = ScreenTimeInsights.lines(apps: apps, hourly: hourly, previousDays: [1_800, 1_800], byThisTime: true, locale: english)
        XCTAssertEqual(Array(lines.prefix(2)), ["About the same as yesterday by this time.", "About the same as your recent average by this time (30 min)."])
    }
}
