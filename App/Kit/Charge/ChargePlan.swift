import Foundation

/// What the battery is doing, in the user's terms. The rules follow AlDente's: the battery charges to
/// the limit, then sails (the adapter powers the Mac, the battery neither charges nor runs down) until
/// it falls more than the sailing range below the limit. A limit below the level pauses charging at
/// the level; the battery runs down only on an explicit Discharge.
public enum ChargeActivity: String, Codable, Equatable, Sendable {
    /// On the adapter, filling up to the limit (or to full without one).
    case charging
    /// On the adapter, which powers the Mac; the battery neither charges nor runs down. Within the
    /// sailing range below the limit this is sailing; above the limit, a pause at the level.
    case holding
    /// Asked for: running from the battery although plugged in, down to the limit.
    case discharging
    /// Asked for: charging to 100% and staying there until unplugged.
    case toppingUp
    /// Not plugged in.
    case onBattery
}

/// A one-off the user asked for. Each ends by itself and the limit takes over again.
public enum ChargeRequest: String, Codable, Equatable, Sendable {
    case none
    /// Run down to the limit while plugged in; ends at the limit.
    case discharge
    /// Charge to 100% and keep it there; ends when unplugged.
    case topUp
}

/// What this Mac's charge control can do.
public struct ChargeAbilities: Equatable, Sendable {
    /// Charging can stop while the adapter keeps powering the Mac.
    public var canHold: Bool
    /// The Mac can run from the battery while plugged in.
    public var canDischarge: Bool

    public init(canHold: Bool, canDischarge: Bool) {
        self.canHold = canHold
        self.canDischarge = canDischarge
    }

    /// What the charge controller's own keys allow.
    public init(keys: ChargeKeys) {
        self.init(canHold: keys.canPause, canDischarge: keys.canDischarge)
    }
}

/// Everything the plan depends on, read just before it is made.
public struct ChargeInput: Equatable, Sendable {
    /// 0…100; NaN when it cannot be read.
    public var level: Double
    public var onAdapter: Bool
    /// The user's limit; nil charges to full.
    public var limit: Int?
    /// How far under the limit the battery may fall before it charges again.
    public var sailing: Int
    public var request: ChargeRequest
    public var abilities: ChargeAbilities
    /// The last plan was charging towards the limit: it carries on up to the limit rather than
    /// stopping as soon as the level enters the sailing range.
    public var wasCharging: Bool

    public init(level: Double, onAdapter: Bool, limit: Int?, sailing: Int = ChargeLimit.defaultSailing, request: ChargeRequest = .none,
                abilities: ChargeAbilities, wasCharging: Bool = false) {
        self.level = level
        self.onAdapter = onAdapter
        self.limit = limit
        self.sailing = ChargeLimit.clampSailing(sailing)
        self.request = request
        self.abilities = abilities
        self.wasCharging = wasCharging
    }
}

/// What to do now, for either way of controlling the charge.
public struct ChargePlan: Equatable, Sendable {
    public var activity: ChargeActivity
    /// The request after one-offs that have ended (top-up unplugged, discharge at the limit).
    public var request: ChargeRequest
    /// Charging towards the limit (remembered while unplugged as false: plugging in within the
    /// sailing range does not start it).
    public var charging: Bool
    /// For macOS's own limit: the level the firmware should keep the battery at or below. Charging:
    /// the limit; holding: the level itself, so the firmware neither charges nor drains; discharging:
    /// the limit, which the firmware drains down to. 100 means no limit.
    public var target: Int
    /// For the charge controller's own keys: what to write.
    public var output: ChargeOutput
}

public enum ChargePlanner {
    public static func plan(_ input: ChargeInput) -> ChargePlan {
        let level = input.level
        let request = remaining(input.request, input)
        let here = holdTarget(level)

        // Nearly empty or unreadable: charge, adapter on, whatever was asked. A top-up already charges.
        guard level.isFinite, level > ChargeLimit.safetyFloor else {
            return ChargePlan(activity: input.onAdapter ? .charging : .onBattery, request: request == .discharge ? .none : request,
                              charging: input.onAdapter, target: request == .topUp ? 100 : input.limit ?? 100, output: .normal)
        }

        switch request {
        case .topUp:
            return ChargePlan(activity: .toppingUp, request: request, charging: true, target: 100, output: .normal)
        case .discharge:
            let limit = input.limit ?? 100
            return ChargePlan(activity: input.onAdapter ? .discharging : .onBattery, request: request, charging: false, target: limit,
                              output: ChargeOutput(inhibit: input.abilities.canHold, adapterOff: true))
        case .none:
            guard let limit = input.limit, input.abilities.canHold else {
                return ChargePlan(activity: input.onAdapter ? .charging : .onBattery, request: request, charging: input.onAdapter,
                                  target: input.limit ?? 100, output: .normal)
            }
            let floor = Double(limit)
            let charging = input.onAdapter && level < floor
                && (input.wasCharging || level < floor - Double(input.sailing))
            let activity: ChargeActivity = input.onAdapter ? (charging ? .charging : .holding) : .onBattery
            return ChargePlan(activity: activity, request: request, charging: charging, target: charging ? limit : here,
                              output: ChargeOutput(inhibit: !charging, adapterOff: false))
        }
    }

    /// The request, or `.none` once it has done its job or cannot be done here.
    static func remaining(_ request: ChargeRequest, _ input: ChargeInput) -> ChargeRequest {
        switch request {
        case .none:
            return .none
        case .topUp:
            return input.onAdapter ? .topUp : .none
        case .discharge:
            guard input.abilities.canDischarge, let limit = input.limit, input.level.isFinite,
                  input.level > Double(limit), input.level > ChargeLimit.safetyFloor else { return .none }
            return .discharge
        }
    }

    /// The level as a target: rounded up, so a battery a fraction above a whole percent is not
    /// drained to it.
    static func holdTarget(_ level: Double) -> Int {
        guard level.isFinite else { return 100 }
        return min(100, max(1, Int(level.rounded(.up))))
    }

    /// Before the Mac sleeps nothing watches the level, so the adapter goes back on (a stopped
    /// charge is safe to keep: the battery cannot overfill or drain because of it).
    public static func forSleep(_ output: ChargeOutput) -> ChargeOutput {
        ChargeOutput(inhibit: output.inhibit, adapterOff: false)
    }
}
