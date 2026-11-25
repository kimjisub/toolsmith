import SQLite3
import XCTest
@testable import ToolsmithKit

final class PowerAndHistoryTests: XCTestCase {
    func testPowerOtherIsWhatIsNotMeasured() {
        var power = PowerBreakdown()
        XCTAssertNil(power.other)
        power.system = 20
        power.gpu = 3
        power.memory = 1
        XCTAssertEqual(power.other, 16)
        power.cpu = 30                                                                    // never below zero
        XCTAssertEqual(power.other, 0)
    }

    func testBatteryHealthAndTexts() {
        var battery = BatteryInfo()
        battery.designCapacity = 6_249
        battery.maximumCapacity = 6_012
        XCTAssertEqual(battery.health!, 96.2, accuracy: 0.05)
        battery.condition = "Good"
        XCTAssertEqual(battery.conditionText(locale: english), "Normal")
        battery.isCharging = true
        battery.minutesRemaining = 80
        XCTAssertEqual(battery.stateText(locale: english), "Charging, 1 hr, 20 min until full")
        battery.isCharging = false
        battery.onAdapter = true
        XCTAssertEqual(battery.stateText(locale: english), "Power adapter connected, charging on hold")
        battery.onAdapter = false
        battery.minutesRemaining = 45
        XCTAssertEqual(battery.stateText(locale: english), "On battery, 45 min left")
    }

    func testEnergyModeFromPmset() {
        XCTAssertEqual(EnergyMode.parse(pmset: "System-wide power settings:\n powermode            2\n sleep 1"), .high)
        XCTAssertEqual(EnergyMode.parse(pmset: " lowpowermode         1\n"), .low)
        XCTAssertNil(EnergyMode.parse(pmset: " sleep 1\n"))
    }

    func testPublicAddressFromCloudflareTrace() {
        let address = PublicAddress.parse(trace: "fl=1\nh=www.cloudflare.com\nip=175.209.161.87\nts=1\nloc=KR\n")
        XCTAssertEqual(address, PublicAddress(ip: "175.209.161.87", country: "KR"))
        XCTAssertEqual(address?.flag, "🇰🇷")
        XCTAssertNil(PublicAddress.parse(trace: "<html>"))
    }

    func testVPNDetection() {
        let addresses = [InterfaceAddress(interface: "en0", address: "192.168.1.10", isIPv6: false),
                         InterfaceAddress(interface: "utun4", address: "100.86.119.109", isIPv6: false),
                         InterfaceAddress(interface: "utun2", address: "fe80::1", isIPv6: true)]
        XCTAssertEqual(VPNDetection.names(tunnelAddresses: addresses), ["Tailscale"])
        XCTAssertEqual(VPNDetection.names(tunnelAddresses: [InterfaceAddress(interface: "utun9", address: "10.1.250.3", isIPv6: false)]), ["VPN"])
        XCTAssertEqual(VPNDetection.physicalInterface(primary: "utun9", addresses: addresses), "en0")
        XCTAssertEqual(VPNDetection.physicalInterface(primary: "en1", addresses: addresses), "en1")
    }

    func testBucketsAverageAndLeaveGaps() {
        let points = [TimedValue(time: 0, value: 10), TimedValue(time: 9, value: 20), TimedValue(time: 35, value: 40), TimedValue(time: 99, value: 1)]
        XCTAssertEqual(HistoryBuckets.average(points, start: 0, end: 40, count: 4), [15, nil, nil, 40])
        XCTAssertEqual(HistoryBuckets.average([], start: 10, end: 0, count: 4), [])
    }

    func testRecentReadingsKeepAnHour() {
        var recent = RecentReadings()
        recent.add(.cpuUser, 1, at: 0)
        recent.add(.cpuUser, 2, at: 1_000)
        recent.add(.cpuUser, 3, at: 3_700)
        XCTAssertEqual(recent.values(.cpuUser, since: 0).map(\.value), [2, 3])
        XCTAssertEqual(recent.values(.cpuUser, since: 2_000).map(\.value), [3])
        XCTAssertTrue(recent.values(.gpu, since: 0).isEmpty)
    }

    func testHistoryStoreAveragesPerMinute() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = try MetricHistoryStore(directory: folder)
        let base: TimeInterval = 1_800_000_000 / 60 * 60
        store.add(Reading(time: base + 1, [(.cpuUser, 10), (.gpu, 1)]))
        store.add(Reading(time: base + 50, [(.cpuUser, 30)]))
        store.add(Reading(time: base + 61, [(.cpuUser, 50), (.gpu, .nan)]))                         // next minute: the first is written
        XCTAssertEqual(store.values(.cpuUser, since: base).map(\.value), [20, 50])       // the minute in progress included
        XCTAssertEqual(store.values(.gpu, since: base).map(\.value), [1])
        store.flush()
        let reopened = try MetricHistoryStore(directory: folder)
        XCTAssertEqual(reopened.values(.cpuUser, since: base).map(\.value), [20, 50])
    }

    func testHistoryStoreFoldsOldMinutesIntoTenMinuteAverages() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = try MetricHistoryStore(directory: folder)
        let base: TimeInterval = 1_800_000_000 / 600 * 600
        for minute in 0..<12 { store.add(Reading(time: base + Double(minute) * 60, [(.cpuUser, Double(minute))])) }
        store.flush()
        store.compact(now: base + MetricHistoryStore.fineRetention + 3_600)
        let values = store.values(.cpuUser, since: base)
        XCTAssertEqual(values.map(\.value), [4.5, 10.5])                                   // minutes 0–9, then 10–11
        XCTAssertEqual(values.first?.time, base + 300)                                      // the middle of the ten minutes
        store.compact(now: base + MetricHistoryStore.retention + 7_200)
        XCTAssertTrue(store.values(.cpuUser, since: 0).isEmpty)
    }

    func testHistoryStoreRemoveAllEmptiesTheFile() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = try MetricHistoryStore(directory: folder)
        let base: TimeInterval = 1_800_000_000 / 60 * 60
        store.add(Reading(time: base + 1, [(.cpuUser, 10)]))
        store.add(Reading(time: base + 61, [(.cpuUser, 50)]))
        store.flush()
        XCTAssertFalse(store.values(.cpuUser, since: base).isEmpty)
        XCTAssertFalse(store.readings(since: base).isEmpty)
        store.removeAll()
        XCTAssertTrue(store.values(.cpuUser, since: base).isEmpty)
        XCTAssertTrue(store.readings(since: base).isEmpty)
        let reopened = try MetricHistoryStore(directory: folder)
        XCTAssertTrue(reopened.values(.cpuUser, since: base).isEmpty)
        XCTAssertTrue(reopened.readings(since: base).isEmpty)
    }

    func testReadingEncodingRoundTripsAndSkipsUnknownMetrics() {
        let reading = Reading(time: 5, [(.cpuUser, 12.5), (.download, 1_234_567.25), (.gpu, .nan)])
        XCTAssertEqual(reading.values, [.cpuUser: 12.5, .download: 1_234_567.25])
        XCTAssertEqual(Reading(time: 5, encoded: reading.encoded), reading)
        var newer = reading.encoded
        newer.append(contentsOf: [200] + [UInt8](repeating: 0, count: 8))                   // a metric a later version added
        newer.append(contentsOf: [1, 2])                                                     // a cut-off tail
        XCTAssertEqual(Reading(time: 5, encoded: newer), reading)
    }

    /// The app quits and opens again 2 minutes later: the readings before come back, and the time
    /// it was not running stays empty in the graphs.
    func testReadingsCarryOnAfterRelaunch() throws {
        let folder = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let base: TimeInterval = 1_800_000_000 / 60 * 60
        let store = try MetricHistoryStore(directory: folder)
        for second in stride(from: 0.0, to: 150, by: 5) { store.add(Reading(time: base + second, [(.cpuUser, second), (.download, 1_000)])) }
        store.flush()                                                                        // quitting

        let relaunch = base + 270
        let reopened = try MetricHistoryStore(directory: folder)
        let readings = reopened.restore(now: relaunch)
        XCTAssertEqual(readings.count, 30)
        XCTAssertEqual(readings.first, Reading(time: base, [(.cpuUser, 0), (.download, 1_000)]))
        XCTAssertEqual(readings.last?.time, base + 145)

        var recent = RecentReadings(readings)
        recent.add(.cpuUser, 99, at: relaunch)
        let buckets = HistoryBuckets.average(recent.values(.cpuUser, since: base), start: base, end: base + 300, count: 10)
        XCTAssertEqual(buckets.prefix(5).compactMap { $0 }.count, 5)                         // 0–150 s: recorded
        XCTAssertEqual(Array(buckets[5..<9]), [nil, nil, nil, nil])                          // 150–270 s: the app was closed
        XCTAssertEqual(buckets[9], 99)

        var graph = History(capacity: 90)
        for reading in readings { graph.push(reading.values[.cpuUser]!, at: reading.time) }
        graph.push(99, at: relaunch)
        XCTAssertEqual(graph.values.suffix(3), [145, nil, 99])
    }

    /// Quit and reopened within one minute: that minute's average covers both sides, not just the second.
    func testRestoreTakesUpTheMinuteInProgress() throws {
        let folder = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let base: TimeInterval = 1_800_000_000 / 60 * 60
        let store = try MetricHistoryStore(directory: folder)
        store.add(Reading(time: base + 5, [(.cpuUser, 10)]))
        store.add(Reading(time: base + 10, [(.cpuUser, 20)]))
        store.flush()
        XCTAssertEqual(try MetricHistoryStore(directory: folder).values(.cpuUser, since: base).map(\.value), [15])   // the part so far

        let reopened = try MetricHistoryStore(directory: folder)
        _ = reopened.restore(now: base + 30)
        reopened.add(Reading(time: base + 30, [(.cpuUser, 30)]))
        reopened.add(Reading(time: base + 65, [(.cpuUser, 70)]))                             // the minute ended: written
        XCTAssertEqual(reopened.values(.cpuUser, since: base).map(\.value), [20, 70])
        reopened.flush()
        XCTAssertEqual(try MetricHistoryStore(directory: folder).values(.cpuUser, since: base).map(\.value), [20, 70])
    }

    func testReadingsOlderThanAnHourAreDropped() throws {
        let folder = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let base: TimeInterval = 1_800_000_000 / 60 * 60
        let store = try MetricHistoryStore(directory: folder)
        store.add(Reading(time: base, [(.cpuUser, 1)]))
        store.add(Reading(time: base + 60, [(.cpuUser, 2)]))                                 // written
        store.add(Reading(time: base + MetricHistoryStore.readingRetention + 30, [(.cpuUser, 3)]))
        store.add(Reading(time: base + MetricHistoryStore.readingRetention + 90, [(.cpuUser, 4)]))
        XCTAssertEqual(try MetricHistoryStore(directory: folder).readings(since: 0).map { $0.values[.cpuUser] }, [3, 4])
        XCTAssertEqual(store.values(.cpuUser, since: 0).count, 4)                             // the minute averages stay 28 days
    }

    /// A file from before readings were kept (schema 0) keeps its averages and gains the readings table.
    func testFileWithoutReadingsIsMigrated() throws {
        let folder = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let path = folder.appendingPathComponent("history-v2.sqlite").path
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(path, &db), SQLITE_OK)
        sqlite3_exec(db, "CREATE TABLE average (metric INTEGER NOT NULL, minutes INTEGER NOT NULL, start INTEGER NOT NULL, value REAL NOT NULL, PRIMARY KEY (metric, minutes, start)) WITHOUT ROWID", nil, nil, nil)
        sqlite3_exec(db, "INSERT INTO average VALUES (1, 1, 30000000, 42)", nil, nil, nil)
        sqlite3_close(db)

        let store = try MetricHistoryStore(directory: folder)
        XCTAssertEqual(store.values(.cpuUser, since: 0).map(\.value), [42])
        store.add(Reading(time: 1_800_000_000, [(.cpuUser, 1)]))
        store.flush()
        XCTAssertEqual(try MetricHistoryStore(directory: folder).readings(since: 0).count, 1)

        XCTAssertEqual(sqlite3_open(path, &db), SQLITE_OK)
        defer { sqlite3_close(db) }
        var statement: OpaquePointer?
        sqlite3_prepare_v2(db, "PRAGMA user_version", -1, &statement, nil)
        defer { sqlite3_finalize(statement) }
        XCTAssertEqual(sqlite3_step(statement), SQLITE_ROW)
        XCTAssertEqual(sqlite3_column_int(statement, 0), MetricHistoryStore.schemaVersion)
    }

    private func temporaryFolder() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }

}
