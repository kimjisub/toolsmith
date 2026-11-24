import Foundation

/// The charge state as the screens show it, whichever way the Mac is controlled.
public struct ChargeSnapshot: Equatable, Sendable {
    public var activity: ChargeActivity
    /// 0…100, nil when unreadable.
    public var level: Double?
    public var onAdapter: Bool
    /// The user's limit; nil charges to full.
    public var limit: Int?
    public var abilities: ChargeAbilities
    /// Positive while the battery charges, negative while it powers the Mac.
    public var batteryWatts: Double?

    public init(activity: ChargeActivity, level: Double?, onAdapter: Bool, limit: Int?, abilities: ChargeAbilities, batteryWatts: Double? = nil) {
        self.activity = activity
        self.level = level
        self.onAdapter = onAdapter
        self.limit = limit
        self.abilities = abilities
        self.batteryWatts = batteryWatts
    }

    /// The level as a whole percent.
    public var percent: Int? { level.map { Int($0.rounded()) } }

    /// Held clearly above the limit: the limit was lowered under the level, and the battery stays put.
    public var heldAboveLimit: Bool {
        guard let percent, let limit else { return false }
        return percent > limit
    }

    /// Discharging makes sense: there is a limit below the level and a way to run from the battery.
    public var canDischarge: Bool { abilities.canDischarge && heldAboveLimit }
    /// Topping up makes sense: plugged in, a limit to lift and room above the level.
    public var canTopUp: Bool { onAdapter && limit != nil && (percent ?? 0) < 100 }
}

public enum ChargeSummary {
    /// One line: what the battery is doing now.
    public static func headline(_ snapshot: ChargeSnapshot, locale: Locale = .app) -> String {
        switch snapshot.activity {
        case .charging:
            if let limit = snapshot.limit, snapshot.abilities.canHold { return localized("Charging to \(limit)%", locale: locale) }
            return (snapshot.percent ?? 0) >= 100 ? localized("Fully charged", locale: locale) : localized("Charging", locale: locale)
        case .holding:
            return localized("Holding at \(snapshot.percent ?? snapshot.limit ?? 0)%", locale: locale)
        case .discharging:
            return localized("Discharging to \(snapshot.limit ?? 0)%", locale: locale)
        case .toppingUp:
            return localized("Charging to 100% once", locale: locale)
        case .onBattery:
            return localized("On battery", locale: locale)
        }
    }

    /// A sentence or two: why, and what comes next. Says outright that a lower limit does not drain.
    public static func explanation(_ snapshot: ChargeSnapshot, locale: Locale = .app) -> String {
        let limit = snapshot.limit ?? 0
        switch snapshot.activity {
        case .charging:
            guard snapshot.limit != nil else { return localized("No limit: the battery charges to full.", locale: locale) }
            guard snapshot.abilities.canHold else {
                return localized("This Mac can’t stop charging while plugged in, so the battery charges to full. The limit only sets where Discharge stops.", locale: locale)
            }
            return localized("At \(limit)% charging stops and the battery is held there.", locale: locale)
        case .holding:
            if snapshot.heldAboveLimit {
                return localized("The adapter powers the Mac and the battery stays where it is. A lower limit doesn’t run the battery down: it comes down as you use the Mac unplugged, or with Discharge.", locale: locale)
            }
            return localized("Charging stopped at the limit. The adapter powers the Mac; the battery neither charges nor runs down.", locale: locale)
        case .discharging:
            return localized("The Mac runs from the battery although plugged in. At \(limit)% the adapter takes over again and the battery is held there.", locale: locale)
        case .toppingUp:
            return localized("The limit is paused until the battery is full or the adapter comes off.", locale: locale)
        case .onBattery:
            guard snapshot.limit != nil, snapshot.abilities.canHold else { return localized("When plugged in, the battery charges to full.", locale: locale) }
            if snapshot.heldAboveLimit { return localized("When plugged in, the battery is held where it is.", locale: locale) }
            return localized("When plugged in, the battery charges to \(limit)%.", locale: locale)
        }
    }
}
