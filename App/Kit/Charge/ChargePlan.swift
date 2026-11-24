import Foundation

/// What the battery is doing, in the user's terms. A limit below the battery's level does not drain
/// it: the battery is held where it is (the adapter powers the Mac) until the user asks to
/// discharge or the level falls by use.
public enum ChargeActivity: String, Codable, Equatable, Sendable {
    /// On the adapter, filling up to the limit (or to full without one).
    case charging
    /// On the adapter, which powers the Mac; the battery neither charges nor runs down.
    case holding
    /// Asked for: running from the battery although plugged in, down to the limit.
    case discharging
    /// Asked for: charging to 100% this once.
    case toppingUp
    /// Not plugged in.
    case onBattery
}

/// A one-off the user asked for. Each ends by itself and the limit takes over again.
public enum ChargeRequest: String, Codable, Equatable, Sendable {
    case none
    /// Run down to the limit while plugged in; ends at the limit.
    case discharge
    /// Charge to 100% once; ends when full or unplugged.
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

    /// macOS's own limit: the firmware stops charging at the target and runs the battery down to a
    /// target below the level.
    public static let system = ChargeAbilities(canHold: true, canDischarge: true)

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
    public var request: ChargeRequest
    public var abilities: ChargeAbilities
    /// The last plan's hold, so the level can sit inside the band below the limit without
    /// switching between charging and holding at every percent.
    public var wasHolding: Bool
    /// The last target handed to macOS's limit, if any.
    public var previousTarget: Int?

    public init(level: Double, onAdapter: Bool, limit: Int?, request: ChargeRequest = .none, abilities: ChargeAbilities,
                wasHolding: Bool = false, previousTarget: Int? = nil) {
        self.level = level
        self.onAdapter = onAdapter
        self.limit = limit
        self.request = request
        self.abilities = abilities
        self.wasHolding = wasHolding
        self.previousTarget = previousTarget
    }
}

/// What to do now, for either way of controlling the charge.
public struct ChargePlan: Equatable, Sendable {
    public var activity: ChargeActivity
    /// The request after one-offs that have ended (top-up full or unplugged, discharge at the limit).
    public var request: ChargeRequest
    /// Charging is stopped by the limit (also while unplugged, so plugging in does not start it).
    public var holding: Bool
    /// For macOS's own limit: the level the firmware keeps the battery at. While holding above the
    /// limit it is the level itself, so the firmware neither charges nor drains; it follows the level
    /// down as the battery is used and never goes under the limit. nil: no limit, or a top-up.
    public var target: Int?
    /// For the helper: what to write to the charge controller.
    public var output: ChargeOutput
}

public enum ChargePlanner {
    /// How far under the limit the level must fall before charging starts again, so the controller
    /// is not switched at every percent. Also how far the hold target trails the level before it is
    /// lowered, so a battery in use is not rewritten at every percent.
    public static let band = 2

    public static func plan(_ input: ChargeInput) -> ChargePlan {
        let level = input.level
        let readable = level.isFinite
        let limit = input.limit
        let request = remaining(input.request, input)

        // Nearly empty or unreadable: charge, adapter on, whatever was asked. A top-up already charges.
        guard readable, level > ChargeLimit.safetyFloor else {
            return ChargePlan(activity: input.onAdapter ? .charging : .onBattery, request: request == .discharge ? .none : request,
                              holding: false, target: limit, output: .normal)
        }

        switch request {
        case .topUp:
            return ChargePlan(activity: input.onAdapter ? .toppingUp : .onBattery, request: request, holding: false, target: nil, output: .normal)
        case .discharge:
            return ChargePlan(activity: input.onAdapter ? .discharging : .onBattery, request: request, holding: true, target: limit,
                              output: ChargeOutput(inhibit: input.abilities.canHold, adapterOff: true))
        case .none:
            guard let limit, input.abilities.canHold else {
                return ChargePlan(activity: input.onAdapter ? .charging : .onBattery, request: request, holding: false,
                                  target: limit, output: .normal)
            }
            let floor = Double(limit), band = Double(Self.band)
            let holding = level >= floor || (input.wasHolding && level > floor - band)
            return ChargePlan(activity: input.onAdapter ? (holding ? .holding : .charging) : .onBattery, request: request,
                              holding: holding, target: holding ? holdTarget(level: level, limit: limit, previous: input.previousTarget) : limit,
                              output: ChargeOutput(inhibit: holding, adapterOff: false))
        }
    }

    /// The request, or `.none` once it has done its job or cannot be done here.
    static func remaining(_ request: ChargeRequest, _ input: ChargeInput) -> ChargeRequest {
        switch request {
        case .none:
            return .none
        case .topUp:
            return input.onAdapter && !(input.level.isFinite && input.level >= 100) ? .topUp : .none
        case .discharge:
            guard input.abilities.canDischarge, let limit = input.limit, input.level.isFinite,
                  input.level > Double(limit), input.level > ChargeLimit.safetyFloor else { return .none }
            return .discharge
        }
    }

    /// Holding above the limit keeps the level the battery has, never more and never under the limit.
    /// The target follows the level down in steps of `band`, and up at once (a top-up or macOS's
    /// occasional full charge left the battery above it: a lower target would drain it).
    static func holdTarget(level: Double, limit: Int, previous: Int?) -> Int {
        let now = min(100, Int(level.rounded()))
        let target: Int
        if let previous, now <= previous, previous - now < band {
            target = previous
        } else {
            target = now
        }
        return min(100, max(limit, target))
    }

    /// Before the Mac sleeps nothing watches the level, so the adapter goes back on (a stopped
    /// charge is safe to keep: the battery cannot overfill or drain because of it).
    public static func forSleep(_ output: ChargeOutput) -> ChargeOutput {
        ChargeOutput(inhibit: output.inhibit, adapterOff: false)
    }
}
