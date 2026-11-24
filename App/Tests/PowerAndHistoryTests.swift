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
        XCTAssertEqual(battery.conditionText, "정상")
        battery.isCharging = true
        battery.minutesRemaining = 80
        XCTAssertEqual(battery.stateText, "충전 중, 다 차기까지 1시간 20분")
        battery.isCharging = false
        battery.onAdapter = true
        XCTAssertEqual(battery.stateText, "어댑터 연결됨, 충전 보류")
        battery.onAdapter = false
        battery.minutesRemaining = 45
        XCTAssertEqual(battery.stateText, "배터리 사용 중, 45분 남음")
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
        store.add([(.cpuUser, 10), (.gpu, 1)], at: base + 1)
        store.add([(.cpuUser, 30)], at: base + 50)
        store.add([(.cpuUser, 50), (.gpu, .nan)], at: base + 61)                         // next minute: the first is written
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
        for minute in 0..<12 { store.add([(.cpuUser, Double(minute))], at: base + Double(minute) * 60) }
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
        store.add([(.cpuUser, 10)], at: base + 1)
        store.add([(.cpuUser, 50)], at: base + 61)
        store.flush()
        XCTAssertFalse(store.values(.cpuUser, since: base).isEmpty)
        store.removeAll()
        XCTAssertTrue(store.values(.cpuUser, since: base).isEmpty)
        XCTAssertTrue(try MetricHistoryStore(directory: folder).values(.cpuUser, since: base).isEmpty)
    }

}
