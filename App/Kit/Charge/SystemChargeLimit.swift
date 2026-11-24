import Foundation

/// macOS's own charge limit (System Settings → Battery → Charging, macOS 26.4 and later on Apple
/// silicon). The firmware holds it, asleep or awake, and drains a battery above it down to it on the
/// adapter. No administrator rights are needed to read or set it.
public struct SystemChargeLimitState: Equatable, Sendable {
    public enum Mode: Equatable, Sendable {
        case on
        case off
        /// "Charge to full this once": the limit is suspended until the battery is full or the
        /// adapter comes off, then returns by itself.
        case toppingUp
    }

    /// 80…100; 100 means no limit.
    public var limit: Int
    public var mode: Mode
    /// The limits macOS offers (80, 85, 90, 95, 100 today).
    public var choices: [Int]

    public init(limit: Int, mode: Mode, choices: [Int]) {
        self.limit = limit
        self.mode = mode
        self.choices = choices.isEmpty ? Self.fallbackChoices : choices.sorted()
    }

    public static let fallbackChoices = [80, 85, 90, 95, 100]

    /// The limit in effect, or nil when the battery may charge to full.
    public var effectiveLimit: Int? { mode == .on && limit < 100 ? limit : nil }

    /// PowerUI's `isMCLCurrentlyEnabled:` value: 1 on, 3 suspended until full, anything else off.
    public static func mode(raw: UInt64) -> Mode {
        switch raw {
        case 1, 2: return .on
        case 3: return .toppingUp
        default: return .off
        }
    }
}

/// What the app keeps beside macOS's own limit. macOS holds one number; while the battery is held
/// above the user's limit that number is the held level, so the user's limit lives here.
public struct SystemChargeMemory: Codable, Equatable, Sendable {
    /// The user's limit (80…99), or nil to charge to full.
    public var limit: Int?
    public var discharging = false
    public var holding = false
    /// The last value written to macOS's limit (100 for none).
    public var written: Int?

    public init(limit: Int? = nil, discharging: Bool = false, holding: Bool = false, written: Int? = nil) {
        self.limit = limit
        self.discharging = discharging
        self.holding = holding
        self.written = written
    }

    /// Takes in what macOS reports. A value this app did not write was set in System Settings (or
    /// another app) and becomes the user's limit; a limit switched off there means no limit. The
    /// first time, macOS's limit is the user's.
    public func reconciled(with state: SystemChargeLimitState) -> SystemChargeMemory {
        var next = self
        switch state.mode {
        case .toppingUp:
            break
        case .off:
            next = SystemChargeMemory(written: written)
        case .on where written != state.limit:
            next = SystemChargeMemory(limit: state.effectiveLimit, written: state.limit)
        case .on:
            break
        }
        return next
    }

    public func input(level: Double, onAdapter: Bool, state: SystemChargeLimitState) -> ChargeInput {
        ChargeInput(level: level, onAdapter: onAdapter, limit: limit,
                    request: state.mode == .toppingUp ? .topUp : discharging ? .discharge : .none,
                    abilities: .system, wasHolding: holding, previousTarget: written)
    }

    /// The value macOS's limit should have under this plan, or nil when it is right already (a
    /// top-up runs, which macOS ends by itself, or no limit is wanted and macOS's is off).
    public static func write(for plan: ChargePlan, state: SystemChargeLimitState) -> Int? {
        guard plan.request != .topUp, plan.target != nil || state.mode != .off else { return nil }
        let wanted = plan.target ?? 100
        return state.mode == .on && state.limit == wanted ? nil : wanted
    }
}
