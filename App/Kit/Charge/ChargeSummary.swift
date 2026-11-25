import Foundation

/// The charge state as the screens show it, whichever way the Mac is controlled.
public struct ChargeSnapshot: Equatable, Sendable {
    public var activity: ChargeActivity
    /// 0…100, nil when unreadable.
    public var level: Double?
    public var onAdapter: Bool
    /// The user's limit; nil charges to full.
    public var limit: Int?
    public var sailing: Int
    public var abilities: ChargeAbilities
    /// Positive while the battery charges, negative while it powers the Mac.
    public var batteryWatts: Double?
    /// Other charge apps running; while there are any, nothing is controlled.
    public var conflicts: [String]

    public init(activity: ChargeActivity, level: Double?, onAdapter: Bool, limit: Int?, sailing: Int = ChargeLimit.defaultSailing,
                abilities: ChargeAbilities, batteryWatts: Double? = nil, conflicts: [String] = []) {
        self.activity = activity
        self.level = level
        self.onAdapter = onAdapter
        self.limit = limit
        self.sailing = sailing
        self.abilities = abilities
        self.batteryWatts = batteryWatts
        self.conflicts = conflicts
    }

    /// The level as a whole percent.
    public var percent: Int? { level.map { Int($0.rounded()) } }

    /// Held clearly above the limit: the limit was lowered under the level, and the battery stays put.
    public var heldAboveLimit: Bool {
        guard let percent, let limit else { return false }
        return percent > limit
    }

    /// Discharging makes sense: there is a limit below the level and a way to run from the battery.
    public var canDischarge: Bool { conflicts.isEmpty && abilities.canDischarge && heldAboveLimit }
    /// Topping up makes sense: plugged in, a limit to lift and room above the level.
    public var canTopUp: Bool { conflicts.isEmpty && onAdapter && limit != nil && (percent ?? 0) < 100 }
    /// The level charging starts again below.
    public var resumeLevel: Int? { limit.map { max(0, $0 - sailing) } }
}

public enum ChargeSummary {
    /// Shown instead of the explanation while another charge app runs.
    public static func conflict(_ names: [String], locale: Locale = .app) -> String? {
        guard !names.isEmpty else { return nil }
        let list = names.formatted(.list(type: .and).locale(locale))
        return localized("\(list) also controls charging. Use one charge app: while it runs, \(AppIdentity.name) changes nothing.", locale: locale)
    }

    /// One line: what the battery is doing now.
    public static func headline(_ snapshot: ChargeSnapshot, locale: Locale = .app) -> String {
        switch snapshot.activity {
        case .charging:
            if let limit = snapshot.limit, snapshot.abilities.canHold { return localized("Charging to \(limit)%", locale: locale) }
            return (snapshot.percent ?? 0) >= 100 ? localized("Fully charged", locale: locale) : localized("Charging", locale: locale)
        case .holding:
            let percent = snapshot.percent ?? snapshot.limit ?? 0
            return snapshot.heldAboveLimit ? localized("Paused at \(percent)%", locale: locale) : localized("Sailing at \(percent)%", locale: locale)
        case .discharging:
            return localized("Discharging to \(snapshot.limit ?? 0)%", locale: locale)
        case .toppingUp:
            return localized("Charging to 100%", locale: locale)
        case .onBattery:
            return localized("On battery", locale: locale)
        }
    }

    /// A sentence or two: why, and what comes next. Says outright that a lower limit does not drain.
    public static func explanation(_ snapshot: ChargeSnapshot, locale: Locale = .app) -> String {
        let limit = snapshot.limit ?? 0
        let resume = snapshot.resumeLevel ?? 0
        switch snapshot.activity {
        case .charging:
            guard snapshot.limit != nil else { return localized("No limit: the battery charges to full.", locale: locale) }
            guard snapshot.abilities.canHold else {
                return localized("This Mac can’t stop charging while plugged in, so the battery charges to full. The limit only sets where Discharge stops.", locale: locale)
            }
            return localized("At \(limit)% charging stops. The battery then sails on the adapter and charges again only below \(resume)%.", locale: locale)
        case .holding:
            if snapshot.heldAboveLimit {
                return localized("The adapter powers the Mac and the battery stays where it is. A lower limit doesn’t run the battery down: it comes down as you use the Mac unplugged, or with Discharge.", locale: locale)
            }
            return localized("The adapter powers the Mac; the battery neither charges nor runs down. It charges again below \(resume)%.", locale: locale)
        case .discharging:
            return localized("The Mac runs from the battery although plugged in. At \(limit)% the adapter takes over again and the battery is held there.", locale: locale)
        case .toppingUp:
            return localized("The limit is lifted until the adapter comes off: the battery charges to 100% and stays there.", locale: locale)
        case .onBattery:
            guard snapshot.limit != nil, snapshot.abilities.canHold else { return localized("When plugged in, the battery charges to full.", locale: locale) }
            if let percent = snapshot.percent, percent >= resume { return localized("When plugged in, the battery stays where it is and charges again below \(resume)%.", locale: locale) }
            return localized("When plugged in, the battery charges to \(limit)%.", locale: locale)
        }
    }
}
