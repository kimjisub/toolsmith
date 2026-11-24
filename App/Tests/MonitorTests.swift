import XCTest
@testable import ToolsmithKit

final class MonitorTests: XCTestCase {
    func testCPUPercentFromTickDeltas() {
        let before = CPUTicks(user: 100, system: 50, idle: 850, nice: 0)
        let after = CPUTicks(user: 200, system: 100, idle: 1_700, nice: 0)
        XCTAssertEqual(CPUTicks.usage(from: before, to: after), 15.0, accuracy: 0.001)       // 150 busy of 1000
        XCTAssertEqual(CPUTicks.usage(from: after, to: after), 0)                             // no time passed
        XCTAssertEqual(CPUTicks.usage(from: after, to: before), 0)                            // counters went backwards
        let allBusy = CPUTicks(user: 300, system: 100, idle: 1_700, nice: 0)
        XCTAssertEqual(CPUTicks.usage(from: after, to: allBusy), 100.0, accuracy: 0.001)
    }

    func testNetworkRate() {
        XCTAssertEqual(NetworkCounters.rate(from: 1_000, to: 3_000, seconds: 2), 1_000)
        XCTAssertEqual(NetworkCounters.rate(from: 3_000, to: 1_000, seconds: 2), 0)           // interface reset
        XCTAssertEqual(NetworkCounters.rate(from: 0, to: 1_000, seconds: 0), 0)
    }

    func testRateText() {
        XCTAssertEqual(ByteSize.rate(0), "0B/s")
        XCTAssertEqual(ByteSize.rate(1_500), "1.5KB/s")
        XCTAssertEqual(ByteSize.rate(2_500_000), "2.5MB/s")
    }

    func testHistoryKeepsTheLatest() {
        var history = History(capacity: 3)
        [1, 2, 3, 4].forEach { history.push($0) }
        XCTAssertEqual(history.values, [2, 3, 4])
        XCTAssertEqual(history.peak, 4)
        XCTAssertEqual(History(capacity: 3).peak, 0)
    }

    func testSMCValues() {
        XCTAssertEqual(SMCValue.decode(type: "sp78", bytes: [0x2D, 0x80]) ?? 0, 45.5, accuracy: 0.001)
        XCTAssertEqual(SMCValue.decode(type: "fpe2", bytes: [0x1F, 0x40]) ?? 0, 2_000, accuracy: 0.001)
        var float: Float = 45.5
        let littleEndian = withUnsafeBytes(of: &float) { Array($0) }
        XCTAssertEqual(SMCValue.decode(type: "flt ", bytes: littleEndian) ?? 0, 45.5, accuracy: 0.001)
        XCTAssertEqual(SMCValue.decode(type: "ui8 ", bytes: [3]) ?? 0, 3, accuracy: 0.001)
        XCTAssertEqual(SMCValue.decode(type: "ui16", bytes: [0x01, 0x02]) ?? 0, 258, accuracy: 0.001)
        XCTAssertNil(SMCValue.decode(type: "ch8*", bytes: [65, 66]))
        XCTAssertNil(SMCValue.decode(type: "flt ", bytes: [1, 2]))                             // too short
    }

    func testTemperatureSummary() {
        let readings: [String: Double] = [
            "Tp01": 52, "Tp05": 58, "Te05": 48,          // CPU cores (Apple silicon)
            "Tg05": 45, "Tg0D": 47,                      // GPU
            "TB1T": 31,                                  // battery
            "Tp0X": 0, "Tp0Y": 250,                      // sensors that are not there or report nonsense
            "TaLP": 28,
        ]
        let summary = TemperatureSummary(readings: readings)
        XCTAssertEqual(summary.cpu ?? 0, (52 + 58 + 48) / 3.0, accuracy: 0.001)   // the average of the cores: steadier than one hot spot
        XCTAssertEqual(summary.cpuPeak ?? 0, 58, accuracy: 0.001)
        // "Tf…" sensors sit near the cores but are not cores (one read 101°C on an idle-fan M2 Pro).
        XCTAssertEqual(TemperatureSummary(readings: ["Tp01": 60, "Tf06": 101]).cpu ?? 0, 60, accuracy: 0.001)
        XCTAssertTrue(TemperatureSummary.wanted("Tp0A")); XCTAssertFalse(TemperatureSummary.wanted("TRD0"))
        XCTAssertEqual(summary.gpu ?? 0, 46, accuracy: 0.001)
        XCTAssertEqual(summary.battery ?? 0, 31, accuracy: 0.001)
        XCTAssertNil(TemperatureSummary(readings: [:]).cpu)
        // Intel names.
        XCTAssertEqual(TemperatureSummary(readings: ["TC0P": 61, "TG0P": 55]).cpu ?? 0, 61, accuracy: 0.001)
    }

    func testFanReading() {
        let fan = FanReading(index: 0, rpm: 2_400, minimum: 1_200, maximum: 6_000)
        XCTAssertEqual(fan.fraction, 0.25, accuracy: 0.001)
        XCTAssertEqual(FanReading(index: 0, rpm: 0, minimum: 0, maximum: 0).fraction, 0)
        XCTAssertEqual(FanReading(index: 0, rpm: 9_000, minimum: 1_200, maximum: 6_000).fraction, 1)
    }

    func testLightSensorKeysSkipPlaceholders() {
        var readings: [String: Double] = ["Tg01": 50, "Tg02": 51, "Tg03": 52, "TB0T": 33, "Tx01": 60]
        for index in 0..<12 { readings[String(format: "Tp%02d", index)] = index < 3 ? 40 : 60 + Double(index) }
        let keys = TemperatureSummary.lightKeys(readings)
        XCTAssertEqual(keys.filter { $0.hasPrefix("Tp") }.count, 8)
        XCTAssertFalse(keys.contains("Tp00"))                                                 // exactly 40.0: a powered-down part
        XCTAssertEqual(keys.filter { $0.hasPrefix("Tg") }, ["Tg01", "Tg02"])
        XCTAssertTrue(keys.contains("TB0T"))
        XCTAssertFalse(keys.contains("Tx01"))
    }
}
