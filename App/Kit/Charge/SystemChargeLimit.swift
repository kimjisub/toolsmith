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
