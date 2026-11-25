import XCTest
@testable import ToolsmithKit

final class ChargeControlTests: XCTestCase {
    private let modern = ChargeKeys(present: ["CHTE", "CHIE"])
    private let adapterOnly = ChargeKeys(present: ["CHIE"])

    private let full = ChargeAbilities(canHold: true, canDischarge: true)

    func testKeySelectionPrefersNewerKeysAndNeverInventsOne() {
        XCTAssertEqual(modern.inhibit.map(\.key), ["CHTE"])
        XCTAssertEqual(modern.inhibit.first?.on, [0x01, 0x00, 0x00, 0x00])
        XCTAssertEqual(ChargeKeys(present: ["CH0B", "CH0C", "CH0J"]).inhibit.map(\.key), ["CH0B", "CH0C"])
        XCTAssertEqual(ChargeKeys(present: ["CH0B"]).inhibit, [])                       // both are needed
        XCTAssertEqual(ChargeKeys(present: ["CH0J", "CH0I"]).adapter?.key, "CH0J")
        XCTAssertEqual(adapterOnly.adapter?.on, [0x08])
        let none = ChargeKeys(present: [])
        XCTAssertFalse(none.canPause); XCTAssertFalse(none.canDischarge)
    }

    func testLimitAndSailingAreClamped() {
        XCTAssertNil(ChargeLimit.clamp(nil))
        XCTAssertNil(ChargeLimit.clamp(0))
        XCTAssertNil(ChargeLimit.clamp(100))
        XCTAssertEqual(ChargeLimit.clamp(10), 20)
        XCTAssertEqual(ChargeLimit.clamp(80), 80)
        XCTAssertEqual(ChargeSettings(limit: 10).limit, 20)
        XCTAssertEqual(ChargeLimit.clampSailing(0), 1)
        XCTAssertEqual(ChargeLimit.clampSailing(50), 20)
        XCTAssertEqual(ChargeSettings().sailing, 5)
    }

    // MARK: The plan (AlDente's rules)

    private func plan(_ level: Double, plugged: Bool = true, limit: Int? = 80, sailing: Int = 5, request: ChargeRequest = .none,
                      abilities: ChargeAbilities? = nil, charging: Bool = false) -> ChargePlan {
        ChargePlanner.plan(ChargeInput(level: level, onAdapter: plugged, limit: limit, sailing: sailing, request: request,
                                       abilities: abilities ?? full, wasCharging: charging))
    }

    func testBelowTheSailingRangeItChargesUpToTheLimit() {
        let low = plan(60)
        XCTAssertEqual(low.activity, .charging)
        XCTAssertEqual(low.target, 80)
        XCTAssertEqual(low.output, .normal)
        // Once charging, it carries on through the sailing range to the limit.
        XCTAssertEqual(plan(78, charging: true).activity, .charging)
        let reached = plan(80, charging: true)
        XCTAssertEqual(reached.activity, .holding)
        XCTAssertFalse(reached.charging)
        XCTAssertEqual(reached.target, 80)
    }

    func testSailingDoesNotChargeUntilTheLevelLeavesTheRange() {
        // 79 is not a reason to charge back to 80: the adapter powers the Mac and the battery sails.
        let sailing = plan(79)
        XCTAssertEqual(sailing.activity, .holding)
        XCTAssertEqual(sailing.target, 79)
        XCTAssertEqual(sailing.output, ChargeOutput(inhibit: true, adapterOff: false))
        XCTAssertEqual(plan(75).activity, .holding)                 // the edge of the range still sails
        XCTAssertEqual(plan(74.5).activity, .charging)              // below it: charge to the limit
        XCTAssertEqual(plan(77, sailing: 2).activity, .charging)
        // Plugged in again inside the range: no top-up charge (AlDente's "micro-charging").
        XCTAssertEqual(plan(77).activity, .holding)
    }

    func testALowerLimitPausesAtTheLevelInsteadOfDraining() {
        let paused = plan(95)
        XCTAssertEqual(paused.activity, .holding)
        XCTAssertEqual(paused.target, 95)
        XCTAssertEqual(paused.output, ChargeOutput(inhibit: true, adapterOff: false))
        XCTAssertEqual(plan(95.2).target, 96)                       // rounded up: never a target under the level
    }

    func testUnplugged() {
        let away = plan(90, plugged: false, charging: true)
        XCTAssertEqual(away.activity, .onBattery)
        XCTAssertFalse(away.charging)
        XCTAssertEqual(away.target, 90)
        XCTAssertEqual(plan(60, plugged: false).target, 60)
    }

    func testDischargeOnlyWhenAskedAndItEndsAtTheLimit() {
        let draining = plan(90, request: .discharge)
        XCTAssertEqual(draining.activity, .discharging)
        XCTAssertEqual(draining.target, 80)
        XCTAssertEqual(draining.output, ChargeOutput(inhibit: true, adapterOff: true))
        let done = plan(80, request: .discharge)
        XCTAssertEqual(done.request, .none)
        XCTAssertEqual(done.activity, .holding)
        XCTAssertEqual(done.output, ChargeOutput(inhibit: true, adapterOff: false))
        XCTAssertEqual(plan(90, limit: nil, request: .discharge).request, .none)
        XCTAssertEqual(plan(90, request: .discharge, abilities: ChargeAbilities(canHold: true, canDischarge: false)).request, .none)
        // Unplugged, the request waits; plugged in again it carries on.
        XCTAssertEqual(plan(90, plugged: false, request: .discharge).request, .discharge)
    }

    func testTopUpChargesToFullAndStaysUntilUnplugged() {
        let topping = plan(85, request: .topUp)
        XCTAssertEqual(topping.activity, .toppingUp)
        XCTAssertEqual(topping.target, 100)
        XCTAssertEqual(topping.output, .normal)
        XCTAssertEqual(plan(100, request: .topUp).request, .topUp)  // full: it stays at 100
        let unplugged = plan(100, plugged: false, request: .topUp)
        XCTAssertEqual(unplugged.request, .none)
        XCTAssertEqual(unplugged.activity, .onBattery)
        XCTAssertEqual(unplugged.target, 100)                       // then the battery runs down by use
    }

    func testWithoutAWayToHoldTheLimitNeverLeavesTheAdapter() {
        let abilities = ChargeAbilities(keys: adapterOnly)
        let above = plan(85, abilities: abilities)
        XCTAssertEqual(above.activity, .charging)
        XCTAssertEqual(above.output, .normal)
        XCTAssertEqual(plan(85, request: .discharge, abilities: abilities).output, ChargeOutput(inhibit: false, adapterOff: true))
    }

    func testNoLimitChargesToFull() {
        let free = plan(90, limit: nil)
        XCTAssertEqual(free.activity, .charging)
        XCTAssertEqual(free.target, 100)
        XCTAssertEqual(free.output, .normal)
    }

    func testTheSafetyFloorAndBrokenReadings() {
        let low = plan(10, request: .discharge)
        XCTAssertEqual(low.output, .normal)
        XCTAssertEqual(low.request, .none)
        XCTAssertEqual(low.activity, .charging)
        XCTAssertEqual(plan(.nan).output, .normal)
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
        next.sailing = 10
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

final class NativeLimitWatchTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_000_000)

    func testAWrittenTargetIsGivenTimeToSettle() {
        var watch = NativeLimitWatch()
        XCTAssertTrue(watch.shouldWrite(97, reported: 80, now: start))
        watch.wrote(97, at: start)
        XCTAssertFalse(watch.shouldWrite(97, reported: 80, now: start + 60))     // the agent applies it within a minute or two
        watch.observe(97, now: start + 70)
        XCTAssertTrue(watch.confirmed)
        XCTAssertFalse(watch.shouldWrite(97, reported: 97, now: start + 80))     // macOS has it
        XCTAssertTrue(watch.shouldWrite(96, reported: 97, now: start + 90))      // a new target
    }

    func testATargetMacOSNeverTakesStopsTheWrites() {
        var watch = NativeLimitWatch()
        watch.wrote(99, at: start)
        watch.observe(80, now: start + 100)
        XCTAssertFalse(watch.failed)
        watch.observe(80, now: start + 200)
        XCTAssertTrue(watch.failed)
        XCTAssertFalse(watch.shouldWrite(98, reported: 80, now: start + 300))
    }

    func testAnotherAppChangingATakenTargetIsWrittenAgain() {
        var watch = NativeLimitWatch()
        watch.wrote(90, at: start)
        watch.observe(90, now: start + 60)
        // Something else set 80 later: write 90 again once the last write has settled.
        watch.observe(80, now: start + 600)
        XCTAssertFalse(watch.failed)
        XCTAssertTrue(watch.shouldWrite(90, reported: 80, now: start + 600))
    }
}

final class ChargeConflictsTests: XCTestCase {
    func testKnownAppsAreFoundByTheirPaths() {
        XCTAssertEqual(ChargeConflicts.detect(["/Applications/Setapp/AlDente Pro.app/Contents/MacOS/AlDente"]), ["AlDente"])
        XCTAssertEqual(ChargeConflicts.detect(["/Library/PrivilegedHelperTools/com.apphousekitchen.aldente-pro-setapp.helper"]), ["AlDente"])
        XCTAssertEqual(ChargeConflicts.detect(["/usr/local/bin/batt daemon"]), ["batt"])
        XCTAssertEqual(ChargeConflicts.detect(["/bin/bash /usr/local/bin/battery maintain 80"]), ["battery"])
        XCTAssertEqual(ChargeConflicts.detect(["/Library/PrivilegedHelperTools/me.mhaeuser.batterytoolkitd"]), ["Battery Toolkit"])
        XCTAssertEqual(ChargeConflicts.detect(["/Applications/Ampere.app/Contents/MacOS/Ampere"]), ["Ampere"])
    }

    func testLookalikesAreNot() {
        XCTAssertEqual(ChargeConflicts.detect(["/usr/libexec/PowerUIAgent", "/usr/bin/batteryd", "/usr/sbin/systemstats",
                                               "/Applications/Toolsmith.app/Contents/MacOS/ToolsmithHelper", "/opt/battle/battalion"]), [])
    }
}

final class ChargeSummaryTests: XCTestCase {
    private let english = Locale(identifier: "en_US")
    private let korean = Locale(identifier: "ko_KR")

    private func snapshot(_ activity: ChargeActivity, _ level: Double, plugged: Bool = true, limit: Int? = 80,
                          abilities: ChargeAbilities = ChargeAbilities(canHold: true, canDischarge: true), conflicts: [String] = []) -> ChargeSnapshot {
        ChargeSnapshot(activity: activity, level: level, onAdapter: plugged, limit: limit, abilities: abilities, conflicts: conflicts)
    }

    func testHeadlinesNameTheState() {
        XCTAssertEqual(ChargeSummary.headline(snapshot(.charging, 60), locale: english), "Charging to 80%")
        XCTAssertEqual(ChargeSummary.headline(snapshot(.holding, 95.2), locale: english), "Paused at 95%")
        XCTAssertEqual(ChargeSummary.headline(snapshot(.holding, 78), locale: english), "Sailing at 78%")
        XCTAssertEqual(ChargeSummary.headline(snapshot(.discharging, 90), locale: english), "Discharging to 80%")
        XCTAssertEqual(ChargeSummary.headline(snapshot(.toppingUp, 90), locale: english), "Charging to 100%")
        XCTAssertEqual(ChargeSummary.headline(snapshot(.charging, 100, limit: nil), locale: english), "Fully charged")
        XCTAssertEqual(ChargeSummary.headline(snapshot(.holding, 95), locale: korean), "95%에서 멈춤")
        XCTAssertEqual(ChargeSummary.headline(snapshot(.holding, 78), locale: korean), "78%에서 항해 중")
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

    func testSailingSaysWhereChargingResumes() {
        XCTAssertTrue(ChargeSummary.explanation(snapshot(.holding, 78), locale: english).contains("below 75%"))
        XCTAssertTrue(ChargeSummary.explanation(snapshot(.onBattery, 77, plugged: false), locale: english).contains("stays where it is"))
        XCTAssertTrue(ChargeSummary.explanation(snapshot(.onBattery, 60, plugged: false), locale: english).contains("charges to 80%"))
    }

    func testAnotherChargeAppTurnsTheControlsOff() {
        let shot = snapshot(.holding, 95, conflicts: ["AlDente"])
        XCTAssertFalse(shot.canDischarge)
        XCTAssertFalse(shot.canTopUp)
        XCTAssertEqual(ChargeSummary.conflict(["AlDente"], locale: english), "AlDente also controls charging. Use one charge app: while it runs, \(AppIdentity.name) changes nothing.")
        XCTAssertNil(ChargeSummary.conflict([], locale: english))
    }

    func testEveryStateHasKoreanText() {
        for activity in [ChargeActivity.charging, .holding, .discharging, .toppingUp, .onBattery] {
            let shot = snapshot(activity, 90, plugged: activity != .onBattery)
            XCTAssertNotEqual(ChargeSummary.explanation(shot, locale: korean), ChargeSummary.explanation(shot, locale: english), "\(activity)")
        }
    }
}
