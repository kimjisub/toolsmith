import XCTest
@testable import ToolsmithKit

final class MonitorReadingsTests: XCTestCase {
    func testCPUSplitsUserAndSystem() {
        let before = CPUTicks(user: 100, system: 50, idle: 850, nice: 0)
        let after = CPUTicks(user: 180, system: 90, idle: 1_710, nice: 20)
        let usage = CPUUsage.between(before, after)
        XCTAssertEqual(usage.user, 10, accuracy: 0.001)                                   // 80 user + 20 nice of 1000 ticks
        XCTAssertEqual(usage.system, 4, accuracy: 0.001)
        XCTAssertEqual(usage.total, 14, accuracy: 0.001)
        XCTAssertEqual(CPUUsage.between(after, before), CPUUsage())                       // counters went backwards
    }

    func testCoreClustersNumberSlowCoresFirst() {
        let clusters = [CoreCluster(name: "Performance", count: 3), CoreCluster(name: "Efficiency", count: 2)]
        XCTAssertEqual(CoreCluster.assign(clusters: clusters, coreCount: 5), [1, 1, 0, 0, 0])
        XCTAssertEqual(CoreCluster.assign(clusters: clusters, coreCount: 4), [0, 0, 0, 0])  // layout does not fit: one kind
        XCTAssertEqual(clusters[0].label(locale: english), "Performance Cores")
        XCTAssertEqual(CoreCluster(name: "Super", count: 6).label(locale: english), "Super Cores")
    }

    func testMemoryBreakdownMatchesActivityMonitor() {
        let page: UInt64 = 16_384
        let memory = MemoryBreakdown(total: 64 * page * 1_000, internalPages: 30_000, purgeablePages: 2_000, externalPages: 10_000,
                                     wiredPages: 5_000, compressorPages: 3_000, pageSize: page, swapUsed: 0, freeLevel: 80)
        XCTAssertEqual(memory.app, 28_000 * page)                                         // purgeable is not app memory
        XCTAssertEqual(memory.cached, 12_000 * page)                                      // files plus purgeable
        XCTAssertEqual(memory.used, 36_000 * page)
        XCTAssertEqual(memory.free, 28_000 * page)                                        // cached files count as free
        XCTAssertEqual(memory.pressure, 20)
        XCTAssertEqual(memory.fractions.reduce(0, +), memory.usedPercent / 100, accuracy: 0.0001)
        XCTAssertEqual(MemoryBreakdown().usedPercent, 0)
    }

    func testCounterRates() {
        let rates = CounterRates.rates(before: ["a": 100, "b": 500], after: ["a": 300, "b": 100, "c": 50], seconds: 2)
        XCTAssertEqual(rates, ["a": 100])                                                 // b restarted, c is new
        XCTAssertEqual(CounterRates.rates(before: ["a": 1], after: ["a": 2], seconds: 0), [:])
    }

    func testTexts() {
        XCTAssertEqual(UptimeText.text(6 * 86_400 + 600, locale: english), "6 days")
        XCTAssertEqual(UptimeText.text(86_400 + 3 * 3_600, locale: english), "1 day, 3 hr")
        XCTAssertEqual(UptimeText.text(3 * 3_600 + 12 * 60, locale: english), "3 hr, 12 min")
        XCTAssertEqual(UptimeText.text(59, locale: english), "0 min")
        XCTAssertEqual(MonitorText.watts(0.45), "450 mW")
        XCTAssertEqual(MonitorText.watts(9.34), "9.3 W")
        XCTAssertEqual(MonitorText.watts(22.7), "23 W")
        XCTAssertEqual(MonitorText.frequency(megahertz: 4_160), "4.16 GHz")
        XCTAssertEqual(MonitorText.frequency(megahertz: 850), "850 MHz")
        XCTAssertEqual(MonitorText.rate(1_500, locale: english), "1.5 KB/s")
        XCTAssertEqual(MonitorText.memory(96 * 1_073_741_824, locale: english), "96 GB")              // binary, as macOS shows memory
        XCTAssertEqual(MonitorText.memory(1_610_612_736, locale: english), "1.5 GB")
        XCTAssertEqual(MonitorText.memory(512, locale: english), "512 B")
    }

    func testFrequencyAveragesRunningTimeOnly() {
        let table = [600.0, 1_200, 2_000]
        let states: [(name: String, residency: Int64)] = [("IDLE", 1_000), ("DOWN", 0), ("V0P2", 100), ("V1P1", 0), ("V2P0", 300)]
        XCTAssertEqual(FrequencyEstimate.average(states: states, table: table)!, (100 * 600 + 300 * 2_000) / 400.0, accuracy: 0.001)
        XCTAssertNil(FrequencyEstimate.average(states: [("IDLE", 500), ("V0P0", 0)], table: table))   // never ran
        // More states than the table: the extra ones run at the top speed.
        XCTAssertEqual(FrequencyEstimate.average(states: [("P1", 0), ("P2", 0), ("P3", 0), ("P4", 10)], table: table)!, 2_000)
    }

    func testClockTableFromVoltageStates() {
        func pair(_ frequency: UInt32, _ voltage: UInt32) -> [UInt8] {
            [frequency, voltage].flatMap { value in (0..<4).map { UInt8(value >> ($0 * 8) & 0xFF) } }
        }
        let hertz = Data(pair(0, 0) + pair(600_000_000, 700) + pair(3_228_000_000, 1_000))
        XCTAssertEqual(FrequencyEstimate.table(fromVoltageStates: hertz), [600, 3_228])
        let kilohertz = Data(pair(912_000, 700) + pair(4_512_000, 1_100))                  // newer chips
        XCTAssertEqual(FrequencyEstimate.table(fromVoltageStates: kilohertz), [912, 4_512])
    }

    func testSensorCatalogNamesAndGroups() {
        let readings = SensorCatalog.readings(["Tp01": 60, "Tp05": 70, "Te04": 50, "Tg0f": 55, "TB0T": 33, "TW0P": 45, "Tx99": 40, "Tp09": 200], locale: english)
        XCTAssertEqual(readings.map(\.label), ["CPU Performance Cores 1", "CPU Performance Cores 2", "CPU Efficiency Cores", "Graphics", "Battery", "Wi-Fi"])
        let summaries = SensorCatalog.summaries(readings)
        XCTAssertEqual(summaries.first?.peak, 70)
        XCTAssertEqual(summaries.first?.average, 65)
        XCTAssertEqual(summaries.count, 5)
    }
}
