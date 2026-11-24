import XCTest
@testable import ToolsmithKit

final class ChargeControlTests: XCTestCase {
    private let modern = ChargeKeys(present: ["CHTE", "CHIE"])
    private let adapterOnly = ChargeKeys(present: ["CHIE"])

    func testKeySelectionPrefersNewerKeysAndNeverInventsOne() {
        XCTAssertEqual(modern.inhibit.map(\.key), ["CHTE"])
        XCTAssertEqual(modern.inhibit.first?.on, [0x01, 0x00, 0x00, 0x00])
        XCTAssertEqual(ChargeKeys(present: ["CH0B", "CH0C", "CH0J"]).inhibit.map(\.key), ["CH0B", "CH0C"])
        XCTAssertEqual(ChargeKeys(present: ["CH0B"]).inhibit, [])                       // both are needed
        XCTAssertEqual(ChargeKeys(present: ["CH0J", "CH0I"]).adapter?.key, "CH0J")
        XCTAssertEqual(adapterOnly.adapter?.on, [0x08])
        let none = ChargeKeys(present: [])
        XCTAssertFalse(none.canPause); XCTAssertFalse(none.canDischarge); XCTAssertFalse(none.canLimit)
        XCTAssertTrue(adapterOnly.canLimit); XCTAssertFalse(adapterOnly.canPause)
    }

    func testLimitIsClamped() {
        XCTAssertNil(ChargeLimit.clamp(nil))
        XCTAssertNil(ChargeLimit.clamp(0))
        XCTAssertNil(ChargeLimit.clamp(100))
        XCTAssertNil(ChargeLimit.clamp(250))
        XCTAssertEqual(ChargeLimit.clamp(20), 50)
        XCTAssertEqual(ChargeLimit.clamp(80), 80)
        XCTAssertEqual(ChargeSettings(limit: 10).limit, 50)
    }

    func testLimitHoldsWithHysteresis() {
        let settings = ChargeSettings(limit: 80)
        let charging = ChargeOutput.normal, holding = ChargeOutput(inhibit: true, adapterOff: false)
        XCTAssertEqual(ChargeDecision.decide(level: 80, settings: settings, keys: modern, current: charging), holding)
        XCTAssertEqual(ChargeDecision.decide(level: 79, settings: settings, keys: modern, current: holding), holding)   // inside the band
        XCTAssertEqual(ChargeDecision.decide(level: 79, settings: settings, keys: modern, current: charging), charging)
        XCTAssertEqual(ChargeDecision.decide(level: 78, settings: settings, keys: modern, current: holding), charging)  // fell below: charge again
    }

    func testWithoutAnInhibitKeyTheLimitIsHeldOnBattery() {
        let settings = ChargeSettings(limit: 80)
        XCTAssertEqual(ChargeDecision.decide(level: 85, settings: settings, keys: adapterOnly, current: .normal),
                       ChargeOutput(inhibit: false, adapterOff: true))
        // Holding on battery uses the wider band: still on battery at 77, charging again at 74.
        let onBattery = ChargeOutput(inhibit: false, adapterOff: true)
        XCTAssertEqual(ChargeDecision.decide(level: 77, settings: settings, keys: adapterOnly, current: onBattery), onBattery)
        XCTAssertEqual(ChargeDecision.decide(level: 74, settings: settings, keys: adapterOnly, current: onBattery), .normal)
        // Pausing needs an inhibit key: asking for it on such a Mac changes nothing.
        XCTAssertEqual(ChargeDecision.decide(level: 50, settings: ChargeSettings(paused: true), keys: adapterOnly, current: .normal), .normal)
    }

    func testPauseDischargeAndTheSafetyFloor() {
        XCTAssertEqual(ChargeDecision.decide(level: 40, settings: ChargeSettings(paused: true), keys: modern, current: .normal),
                       ChargeOutput(inhibit: true, adapterOff: false))
        XCTAssertEqual(ChargeDecision.decide(level: 60, settings: ChargeSettings(discharging: true), keys: modern, current: .normal),
                       ChargeOutput(inhibit: false, adapterOff: true))
        // Nearly empty: back to normal whatever was asked. A broken reading too.
        XCTAssertEqual(ChargeDecision.decide(level: 10, settings: ChargeSettings(limit: 50, paused: true, discharging: true), keys: modern, current: .normal), .normal)
        XCTAssertEqual(ChargeDecision.decide(level: .nan, settings: ChargeSettings(paused: true), keys: modern, current: .normal), .normal)
    }

    func testDischargeEndsAtTheLimitAndSleepPutsTheAdapterBack() {
        let settings = ChargeSettings(limit: 70, discharging: true)
        XCTAssertEqual(ChargeDecision.decide(level: 75, settings: settings, keys: modern, current: .normal),
                       ChargeOutput(inhibit: true, adapterOff: true))
        XCTAssertTrue(ChargeDecision.dischargeDone(level: 70, settings: settings))
        XCTAssertEqual(ChargeDecision.decide(level: 69, settings: settings, keys: modern, current: .normal), .normal)
        XCTAssertFalse(ChargeDecision.dischargeDone(level: 40, settings: ChargeSettings(discharging: true)))
        XCTAssertTrue(ChargeDecision.dischargeDone(level: 15, settings: ChargeSettings(discharging: true)))
        XCTAssertEqual(ChargeDecision.forSleep(ChargeOutput(inhibit: true, adapterOff: true)), ChargeOutput(inhibit: true, adapterOff: false))
    }

    func testSystemLimitModesAndChoices() {
        XCTAssertEqual(SystemChargeLimitState.mode(raw: 1), .on)
        XCTAssertEqual(SystemChargeLimitState.mode(raw: 3), .toppingUp)
        XCTAssertEqual(SystemChargeLimitState.mode(raw: 0), .off)
        XCTAssertEqual(SystemChargeLimitState(limit: 80, mode: .on, choices: [100, 80, 90]).choices, [80, 90, 100])
        XCTAssertEqual(SystemChargeLimitState(limit: 80, mode: .on, choices: []).choices, SystemChargeLimitState.fallbackChoices)
        XCTAssertEqual(SystemChargeLimitState(limit: 85, mode: .on, choices: []).effectiveLimit, 85)
        XCTAssertNil(SystemChargeLimitState(limit: 100, mode: .on, choices: []).effectiveLimit)
        XCTAssertNil(SystemChargeLimitState(limit: 80, mode: .toppingUp, choices: []).effectiveLimit)
        XCTAssertNil(SystemChargeLimitState(limit: 80, mode: .off, choices: []).effectiveLimit)
    }

    func testStatusRoundTripsAndRequirementNamesTheTeam() throws {
        let status = ChargeStatus(settings: ChargeSettings(limit: 80), output: .normal, canPause: false, canDischarge: true, level: 79.5)
        XCTAssertEqual(try JSONDecoder().decode(ChargeStatus.self, from: JSONEncoder().encode(status)), status)
        XCTAssertEqual(ChargeHelperIdentity.requirement(identifier: "com.example.app"),
                       "anchor apple generic and identifier \"com.example.app\" and certificate leaf[subject.OU] = \"\(AppIdentity.teamID)\"")
    }
}
