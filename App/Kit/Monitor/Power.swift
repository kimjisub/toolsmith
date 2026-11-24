import Foundation

/// Where the power goes, in watts. Each part is nil when this Mac does not report it.
public struct PowerBreakdown: Equatable, Sendable {
    /// Everything the Mac draws.
    public var system: Double?
    /// What comes in from the power adapter.
    public var adapter: Double?
    /// Positive while the battery charges, negative while it powers the Mac.
    public var battery: Double?
    public var cpu: Double?
    public var gpu: Double?
    public var neuralEngine: Double?
    public var memory: Double?

    public init() {}

    /// What the system draws beyond the parts measured on their own (display, SSD, radios, and the
    /// CPU when it is not measured).
    public var other: Double? {
        guard let system else { return nil }
        let known = [cpu, gpu, neuralEngine, memory].compactMap { $0 }.reduce(0, +)
        return max(0, system - known)
    }
}

/// The battery, as the system and its charge controller describe it.
public struct BatteryInfo: Equatable, Sendable {
    /// 0…100
    public var level: Double = 0
    public var isCharging = false
    public var onAdapter = false
    public var isFull = false
    /// Minutes until empty or full; nil while the system is still estimating.
    public var minutesRemaining: Int?
    public var cycleCount: Int?
    /// mAh the battery held when new, and what it holds now when full.
    public var designCapacity: Int?
    public var maximumCapacity: Int?
    public var temperature: Double?
    /// The system's own verdict ("Good", "Fair", "Poor", "Check Battery"…).
    public var condition: String?
    public var adapterWatts: Int?

    public init() {}

    /// How much of its original capacity the battery keeps (0…100).
    public var health: Double? {
        guard let designCapacity, let maximumCapacity, designCapacity > 0 else { return nil }
        return min(100, Double(maximumCapacity) / Double(designCapacity) * 100)
    }

    /// The system's verdict in the app's language.
    public var conditionText: String? { conditionText(locale: .app) }

    public func conditionText(locale: Locale) -> String? {
        guard let condition else { return nil }
        switch condition.lowercased() {
        case "good", "normal": return localized("Normal", locale: locale)
        case "fair": return localized("Fair", locale: locale)
        case "poor": return localized("Poor", locale: locale)
        case "check battery", "service recommended": return localized("Service Recommended", locale: locale)
        default: return condition
        }
    }

    /// "Charging, 1 hr, 20 min until full", "Power adapter connected", "On battery, 3 hr left"
    public var stateText: String { stateText(locale: .app) }

    public func stateText(locale: Locale) -> String {
        let remaining = minutesRemaining.map { DurationText.units(minutes: $0, allowed: [.hours, .minutes], locale: locale) }
        if isCharging {
            return remaining.map { localized("Charging, \($0) until full", locale: locale) } ?? localized("Charging", locale: locale)
        }
        if onAdapter {
            return isFull ? localized("Fully charged, power adapter connected", locale: locale) : localized("Power adapter connected, charging on hold", locale: locale)
        }
        return remaining.map { localized("On battery, \($0) left", locale: locale) } ?? localized("On battery", locale: locale)
    }
}

/// The energy mode chosen in System Settings → Battery.
public enum EnergyMode: Int, Sendable {
    case automatic = 0, low = 1, high = 2

    public var label: String {
        switch self {
        case .automatic: return localized("Automatic")
        case .low: return localized("Low Power")
        case .high: return localized("High Power")
        }
    }

    /// Reads the "powermode" line of `pmset -g`.
    public static func parse(pmset output: String) -> EnergyMode? {
        for line in output.split(separator: "\n") {
            let parts = line.split(separator: " ", omittingEmptySubsequences: true)
            if parts.count >= 2, parts[0] == "powermode" || parts[0] == "lowpowermode" {
                guard let value = Int(parts[1]) else { continue }
                if parts[0] == "lowpowermode" { return value == 1 ? .low : nil }
                return EnergyMode(rawValue: value)
            }
        }
        return nil
    }
}

/// A Bluetooth accessory's battery (keyboard, trackpad, mouse).
public struct AccessoryBattery: Equatable, Sendable, Identifiable {
    public let name: String
    public let level: Double
    public var id: String { name }

    public init(name: String, level: Double) {
        self.name = name
        self.level = level
    }
}
