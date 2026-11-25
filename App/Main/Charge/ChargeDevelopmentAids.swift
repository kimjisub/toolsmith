import Foundation
import ToolsmithKit

#if TOOLSMITH_DEV
extension ChargeModule {
    /// Development flags this module answers (see CLAUDE.md, "Building and checking").
    func runDevelopmentAid(_ arguments: [String]) {
        if arguments.contains("--print-charge-status"), let charge {
            // Development aid: what battery charge control reports on this Mac and build, and quit.
            charge.refresh()
            print("charge state: \(charge.state) signedByTeam: \(ChargeController.isSignedByTeam)")
            charge.install()
            print("after install: \(charge.state)")
            exit(0)
        }
    }

    /// `--charge-demo <state>`: a made-up charge state for pictures (charging, sailing, held-above,
    /// discharging, topping-up, on-battery, cannot-hold, conflict). While it is set the controller reads and
    /// writes nothing.
    static func demoSnapshot(_ arguments: [String]) -> ChargeSnapshot? {
        guard let index = arguments.firstIndex(of: "--charge-demo"), index + 1 < arguments.count else { return nil }
        let full = ChargeAbilities(canHold: true, canDischarge: true)
        switch arguments[index + 1] {
        case "charging":
            return ChargeSnapshot(activity: .charging, level: 62, onAdapter: true, limit: 80, abilities: full, batteryWatts: 41.6)
        case "holding", "sailing":
            return ChargeSnapshot(activity: .holding, level: 77, onAdapter: true, limit: 80, abilities: full, batteryWatts: 0)
        case "conflict":
            return ChargeSnapshot(activity: .holding, level: 97, onAdapter: true, limit: 80, abilities: full, batteryWatts: 0, conflicts: ["AlDente"])
        case "held-above":
            return ChargeSnapshot(activity: .holding, level: 95, onAdapter: true, limit: 80, abilities: full, batteryWatts: 0)
        case "discharging":
            return ChargeSnapshot(activity: .discharging, level: 91, onAdapter: true, limit: 80, abilities: full, batteryWatts: -18.4)
        case "topping-up":
            return ChargeSnapshot(activity: .toppingUp, level: 86, onAdapter: true, limit: 80, abilities: full, batteryWatts: 35.2)
        case "on-battery":
            return ChargeSnapshot(activity: .onBattery, level: 74, onAdapter: false, limit: 80, abilities: full, batteryWatts: -9.7)
        case "cannot-hold":
            return ChargeSnapshot(activity: .charging, level: 88, onAdapter: true, limit: 80,
                                  abilities: ChargeAbilities(canHold: false, canDischarge: true), batteryWatts: 22.0)
        default:
            return nil
        }
    }
}
#endif
