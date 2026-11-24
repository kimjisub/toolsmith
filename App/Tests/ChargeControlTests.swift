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
        XCTAssertFalse(none.canPause); XCTAssertFalse(none.canDischarge)
        XCTAssertEqual(ChargeAbilities(keys: adapterOnly), ChargeAbilities(canHold: false, canDischarge: true))
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

    // MARK: The plan

    private func plan(_ level: Double, plugged: Bool = true, limit: Int? = 80, request: ChargeRequest = .none,
                      abilities: ChargeAbilities = .system, holding: Bool = false, target: Int? = nil) -> ChargePlan {
        ChargePlanner.plan(ChargeInput(level: level, onAdapter: plugged, limit: limit, request: request, abilities: abilities,
                                       wasHolding: holding, previousTarget: target))
    }

    func testBelowTheLimitItCharges() {
        let below = plan(60)
        XCTAssertEqual(below.activity, .charging)
        XCTAssertEqual(below.target, 80)
        XCTAssertEqual(below.output, .normal)
        XCTAssertEqual(plan(60, limit: nil).target, nil)
        XCTAssertEqual(plan(60, limit: nil).activity, .charging)
    }

    func testLoweringTheLimitHoldsInsteadOfDraining() {
        // 100 → 80 with the battery at 95: hold at 95, not run down to 80.
        let held = plan(95, target: 100)
        XCTAssertEqual(held.activity, .holding)
        XCTAssertEqual(held.target, 95)
        XCTAssertEqual(held.output, ChargeOutput(inhibit: true, adapterOff: false))
        // The helper holds the same way, whichever Mac: the adapter stays on.
        XCTAssertEqual(plan(95, abilities: ChargeAbilities(keys: modern)).output, ChargeOutput(inhibit: true, adapterOff: false))
    }

    func testTheHoldTargetFollowsTheLevelDownButNeverUnderTheLimit() {
        XCTAssertEqual(plan(94, holding: true, target: 95).target, 95)              // one point: not rewritten
        XCTAssertEqual(plan(93, plugged: false, holding: true, target: 95).target, 93)
        XCTAssertEqual(plan(78.6, plugged: false, holding: true, target: 81).target, 80)
        // Above the target (after a full charge macOS made): the target rises at once, so nothing drains.
        XCTAssertEqual(plan(99.6, holding: true, target: 90).target, 100)
        XCTAssertEqual(ChargePlanner.holdTarget(level: 95.4, limit: 80, previous: nil), 95)
    }

    func testTheBandBelowTheLimitKeepsTheLastState() {
        XCTAssertEqual(plan(79, holding: true).activity, .holding)
        XCTAssertEqual(plan(79, holding: false).activity, .charging)
        XCTAssertEqual(plan(78, holding: true).activity, .charging)
        XCTAssertEqual(plan(79, holding: true).target, 80)
    }

    func testUnpluggedTheHoldIsRemembered() {
        let away = plan(90, plugged: false, holding: true, target: 90)
        XCTAssertEqual(away.activity, .onBattery)
        XCTAssertTrue(away.holding)
        XCTAssertEqual(away.output, ChargeOutput(inhibit: true, adapterOff: false))
    }

    func testDischargeOnlyWhenAskedAndItEndsAtTheLimit() {
        let draining = plan(90, request: .discharge, holding: true, target: 90)
        XCTAssertEqual(draining.activity, .discharging)
        XCTAssertEqual(draining.target, 80)
        XCTAssertEqual(draining.output, ChargeOutput(inhibit: true, adapterOff: true))
        // At the limit it ends and the battery is held there.
        let done = plan(80, request: .discharge, holding: true)
        XCTAssertEqual(done.request, .none)
        XCTAssertEqual(done.activity, .holding)
        XCTAssertEqual(done.output, ChargeOutput(inhibit: true, adapterOff: false))
        // Nothing to run down to, or no way to: the request is dropped.
        XCTAssertEqual(plan(90, limit: nil, request: .discharge).request, .none)
        XCTAssertEqual(plan(90, request: .discharge, abilities: ChargeAbilities(canHold: true, canDischarge: false)).request, .none)
        // Unplugged, the request waits; plugged in again it carries on.
        XCTAssertEqual(plan(90, plugged: false, request: .discharge).request, .discharge)
        XCTAssertEqual(plan(90, plugged: false, request: .discharge).activity, .onBattery)
    }

    func testTopUpChargesToFullOnceThenTheLimitReturns() {
        let topping = plan(85, request: .topUp, holding: true, target: 85)
        XCTAssertEqual(topping.activity, .toppingUp)
        XCTAssertNil(topping.target)
        XCTAssertEqual(topping.output, .normal)
        // Full: back to the limit, held at the level reached.
        let full = plan(100, request: .topUp)
        XCTAssertEqual(full.request, .none)
        XCTAssertEqual(full.activity, .holding)
        XCTAssertEqual(full.target, 100)
        // Unplugged: the top-up is over.
        XCTAssertEqual(plan(90, plugged: false, request: .topUp).request, .none)
    }

    func testWithoutAWayToHoldTheLimitNeverLeavesTheAdapter() {
        let abilities = ChargeAbilities(keys: adapterOnly)
        let above = plan(85, abilities: abilities)
        XCTAssertEqual(above.activity, .charging)
        XCTAssertEqual(above.output, .normal)                        // the old behaviour ran it from the battery
        // Discharging still works, when asked, and leaves only the adapter.
        XCTAssertEqual(plan(85, request: .discharge, abilities: abilities).output, ChargeOutput(inhibit: false, adapterOff: true))
    }

    func testTheSafetyFloorAndBrokenReadings() {
        let low = plan(10, request: .discharge, holding: true)
        XCTAssertEqual(low.output, .normal)
        XCTAssertEqual(low.request, .none)
        XCTAssertEqual(low.activity, .charging)
        XCTAssertEqual(plan(.nan, holding: true).output, .normal)
        XCTAssertEqual(plan(.nan, request: .topUp).request, .topUp)
    }

    func testSleepPutsTheAdapterBack() {
        XCTAssertEqual(ChargePlanner.forSleep(ChargeOutput(inhibit: true, adapterOff: true)), ChargeOutput(inhibit: true, adapterOff: false))
    }

    func testSettingsFromTheFirstHelperStillRead() throws {
        let old = Data(#"{"limit":80,"paused":true,"discharging":false}"#.utf8)
        let settings = try JSONDecoder().decode(ChargeSettings.self, from: old)
        XCTAssertEqual(settings, ChargeSettings(limit: 80))
        var next = settings
        next.request = .topUp
        XCTAssertEqual(next.request, .topUp)
        XCTAssertFalse(next.discharging)
        XCTAssertEqual(try JSONDecoder().decode(ChargeSettings.self, from: JSONEncoder().encode(next)), next)
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
        let status = ChargeStatus(settings: ChargeSettings(limit: 80), output: .normal, canPause: false, canDischarge: true, level: 79.5, activity: .holding)
        XCTAssertEqual(try JSONDecoder().decode(ChargeStatus.self, from: JSONEncoder().encode(status)), status)
        // A version 1 helper's report has no activity.
        let old = Data(#"{"version":1,"settings":{"limit":80,"paused":false,"discharging":false},"output":{"inhibit":true,"adapterOff":false},"canPause":true,"canDischarge":true}"#.utf8)
        XCTAssertEqual(try JSONDecoder().decode(ChargeStatus.self, from: old).version, 1)
        XCTAssertEqual(ChargeHelperIdentity.requirement(identifier: "com.example.app"),
                       "anchor apple generic and identifier \"com.example.app\" and certificate leaf[subject.OU] = \"\(AppIdentity.teamID)\"")
    }
}

final class SystemChargeMemoryTests: XCTestCase {
    private func state(_ limit: Int, _ mode: SystemChargeLimitState.Mode = .on) -> SystemChargeLimitState {
        SystemChargeLimitState(limit: limit, mode: mode, choices: [])
    }

    func testTheFirstReadAdoptsMacOSsLimit() {
        XCTAssertEqual(SystemChargeMemory().reconciled(with: state(85)), SystemChargeMemory(limit: 85, written: 85))
        XCTAssertEqual(SystemChargeMemory().reconciled(with: state(100)), SystemChargeMemory(limit: nil, written: 100))
    }

    func testOurOwnHoldValueIsNotMistakenForANewLimit() {
        let memory = SystemChargeMemory(limit: 80, holding: true, written: 95)
        XCTAssertEqual(memory.reconciled(with: state(95)), memory)
        // Changed in System Settings: that is the new limit, and a discharge under way stops.
        let changed = SystemChargeMemory(limit: 80, discharging: true, written: 80).reconciled(with: state(90))
        XCTAssertEqual(changed, SystemChargeMemory(limit: 90, written: 90))
        XCTAssertEqual(memory.reconciled(with: state(95, .off)).limit, nil)
        XCTAssertEqual(memory.reconciled(with: state(95, .toppingUp)), memory)
    }

    func testLoweringTheLimitWritesTheLevelNotTheLimit() {
        // The user picks 80 with the battery at 95 on the adapter: macOS gets 95.
        let memory = SystemChargeMemory(limit: 80, written: 100)
        let current = state(100)
        let plan = ChargePlanner.plan(memory.input(level: 95, onAdapter: true, state: current))
        XCTAssertEqual(plan.activity, .holding)
        XCTAssertEqual(SystemChargeMemory.write(for: plan, state: current), 95)
        // Asked to discharge: macOS gets the limit, and runs the battery down to it.
        var draining = memory
        draining.discharging = true
        let drain = ChargePlanner.plan(draining.input(level: 95, onAdapter: true, state: state(95)))
        XCTAssertEqual(drain.activity, .discharging)
        XCTAssertEqual(SystemChargeMemory.write(for: drain, state: state(95)), 80)
    }

    func testNothingIsWrittenWhenMacOSAlreadyHasItOrTopsUp() {
        let memory = SystemChargeMemory(limit: 80, holding: true, written: 95)
        let plan = ChargePlanner.plan(memory.input(level: 95, onAdapter: true, state: state(95)))
        XCTAssertNil(SystemChargeMemory.write(for: plan, state: state(95)))
        let topping = ChargePlanner.plan(memory.input(level: 90, onAdapter: true, state: state(95, .toppingUp)))
        XCTAssertEqual(topping.activity, .toppingUp)
        XCTAssertNil(SystemChargeMemory.write(for: topping, state: state(95, .toppingUp)))
        // No limit: macOS's limit sits at 100.
        let free = ChargePlanner.plan(SystemChargeMemory(written: 80).input(level: 50, onAdapter: true, state: state(80)))
        XCTAssertEqual(SystemChargeMemory.write(for: free, state: state(80)), 100)
    }
}

final class ChargeSummaryTests: XCTestCase {
    private let english = Locale(identifier: "en_US")
    private let korean = Locale(identifier: "ko_KR")

    private func snapshot(_ activity: ChargeActivity, _ level: Double, plugged: Bool = true, limit: Int? = 80,
                          abilities: ChargeAbilities = .system) -> ChargeSnapshot {
        ChargeSnapshot(activity: activity, level: level, onAdapter: plugged, limit: limit, abilities: abilities)
    }

    func testHeadlinesNameTheState() {
        XCTAssertEqual(ChargeSummary.headline(snapshot(.charging, 60), locale: english), "Charging to 80%")
        XCTAssertEqual(ChargeSummary.headline(snapshot(.holding, 95.2), locale: english), "Holding at 95%")
        XCTAssertEqual(ChargeSummary.headline(snapshot(.discharging, 90), locale: english), "Discharging to 80%")
        XCTAssertEqual(ChargeSummary.headline(snapshot(.toppingUp, 90), locale: english), "Charging to 100% once")
        XCTAssertEqual(ChargeSummary.headline(snapshot(.charging, 100, limit: nil), locale: english), "Fully charged")
        XCTAssertEqual(ChargeSummary.headline(snapshot(.holding, 95), locale: korean), "95%에서 유지 중")
        XCTAssertEqual(ChargeSummary.headline(snapshot(.discharging, 90), locale: korean), "80%까지 방전 중")
    }

    func testAHoldAboveTheLimitSaysItDoesNotDrain() {
        let above = snapshot(.holding, 95)
        XCTAssertTrue(above.heldAboveLimit)
        XCTAssertTrue(above.canDischarge)
        XCTAssertTrue(ChargeSummary.explanation(above, locale: english).contains("doesn’t run the battery down"))
        XCTAssertFalse(snapshot(.holding, 80).canDischarge)
        XCTAssertFalse(snapshot(.holding, 95, abilities: ChargeAbilities(canHold: true, canDischarge: false)).canDischarge)
    }

    func testTopUpNeedsTheAdapterALimitAndRoom() {
        XCTAssertTrue(snapshot(.holding, 80).canTopUp)
        XCTAssertFalse(snapshot(.onBattery, 80, plugged: false).canTopUp)
        XCTAssertFalse(snapshot(.charging, 60, limit: nil).canTopUp)
        XCTAssertFalse(snapshot(.holding, 100).canTopUp)
    }

    func testAMacThatCannotHoldSaysSo() {
        let text = ChargeSummary.explanation(snapshot(.charging, 85, abilities: ChargeAbilities(canHold: false, canDischarge: true)), locale: english)
        XCTAssertTrue(text.hasPrefix("This Mac can’t stop charging"))
        XCTAssertEqual(ChargeSummary.headline(snapshot(.charging, 85, abilities: ChargeAbilities(canHold: false, canDischarge: true)), locale: english), "Charging")
    }

    func testEveryStateHasKoreanText() {
        for activity in [ChargeActivity.charging, .holding, .discharging, .toppingUp, .onBattery] {
            let shot = snapshot(activity, 90, plugged: activity != .onBattery)
            XCTAssertNotEqual(ChargeSummary.explanation(shot, locale: korean), ChargeSummary.explanation(shot, locale: english), "\(activity)")
        }
    }
}
