import XCTest
@testable import ToolsmithKit

final class FanControlTests: XCTestCase {
    func testParsesOnlyKnownCommands() {
        XCTAssertEqual(FanCommand(line: "set 0 3000"), .set(fan: 0, rpm: 3_000))
        XCTAssertEqual(FanCommand(line: "  set 1 4500.5 \n"), .set(fan: 1, rpm: 4_500.5))
        XCTAssertEqual(FanCommand(line: "auto"), .auto)
        XCTAssertEqual(FanCommand(line: "ping"), .ping)
        XCTAssertNil(FanCommand(line: "set 0"))
        XCTAssertNil(FanCommand(line: "set -1 3000"))
        XCTAssertNil(FanCommand(line: "set 0 abc"))
        XCTAssertNil(FanCommand(line: "set 99 3000"))                 // no Mac has that many fans
        XCTAssertNil(FanCommand(line: "set 0 nan"))
        XCTAssertNil(FanCommand(line: "rm -rf /"))
        XCTAssertNil(FanCommand(line: ""))
        XCTAssertNil(FanCommand(line: String(repeating: "a", count: 500)))
    }

    func testCommandRoundTrip() {
        XCTAssertEqual(FanCommand(line: FanCommand.set(fan: 1, rpm: 3_200).line), .set(fan: 1, rpm: 3_200))
        XCTAssertEqual(FanCommand(line: FanCommand.auto.line), .auto)
    }

    func testTargetIsClampedToTheFansOwnRange() {
        XCTAssertEqual(FanLimits.clamp(1_000, minimum: 2_317, maximum: 6_800), 2_317)      // never below the fan's slowest
        XCTAssertEqual(FanLimits.clamp(9_000, minimum: 2_317, maximum: 6_800), 6_800)
        XCTAssertEqual(FanLimits.clamp(4_000, minimum: 2_317, maximum: 6_800), 4_000)
        XCTAssertNil(FanLimits.clamp(4_000, minimum: 0, maximum: 0))                        // range unknown: refuse
        XCTAssertNil(FanLimits.clamp(4_000, minimum: 6_800, maximum: 2_317))
    }

    func testFractionToRPM() {
        XCTAssertEqual(FanLimits.rpm(fraction: 0, minimum: 2_000, maximum: 6_000), 2_000)
        XCTAssertEqual(FanLimits.rpm(fraction: 0.5, minimum: 2_000, maximum: 6_000), 4_000)
        XCTAssertEqual(FanLimits.rpm(fraction: 1.7, minimum: 2_000, maximum: 6_000), 6_000)
    }

    func testTooHotForcesAutomatic() {
        XCTAssertFalse(FanLimits.mustReturnToAutomatic(hottestCore: 80))
        XCTAssertTrue(FanLimits.mustReturnToAutomatic(hottestCore: 95))
        // With no temperature to watch, the guard cannot work: the fans must not be held.
        XCTAssertTrue(FanLimits.mustReturnToAutomatic(hottestCore: nil))
    }

    func testEncodesValuesTheWayTheyDecode() {
        for (type, value) in [("flt ", 3_456.0), ("fpe2", 3_456.0), ("ui8 ", 1.0), ("ui16", 300.0)] {
            let bytes = SMCValue.encode(type: type, value: value)
            XCTAssertNotNil(bytes, type)
            XCTAssertEqual(SMCValue.decode(type: type, bytes: bytes ?? []) ?? -1, value, accuracy: 0.26, type)
        }
        XCTAssertNil(SMCValue.encode(type: "ch8*", value: 1))
        XCTAssertNil(SMCValue.encode(type: "ui8 ", value: 300))                             // does not fit
        XCTAssertNil(SMCValue.encode(type: "fpe2", value: -1))
    }

    func testSocketPathIsPerUser() {
        XCTAssertEqual(FanHelperProtocol.socketPath(uid: 501), "/var/run/\(AppIdentity.bundleID).fan.501.sock")
    }
}
