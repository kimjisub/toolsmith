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

/// macOS's own charge limit driven to any percentage. PowerUIAgent (root) keeps the limit in its
/// preferences, registers it with powerd, and the firmware enforces it, asleep too, draining a battery
/// above it. Its client interface (System Settings' slider) takes only the listed values and quietly
/// ignores others (seen on macOS 27.0.1), so the helper writes the preferences itself and asks the
/// agent to reload them. The method is the one the open-source tools ampere (az-code-lab/ampere)
/// and batt (charlie0129/batt) use.
public enum NativeChargeLimit {
    /// The agent's domain, in root's preferences (where a root process's current-user writes land).
    public static let domain = "com.apple.smartcharging.topoffprotection"
    /// 1 while the limit is on.
    public static let featureStateKey = "MCLFeatureState"
    /// The target, in percent.
    public static let limitKey = "mclLimitValue"
    /// The Darwin notification the agent reloads its preferences on.
    public static let reloadNotification = "com.apple.smartcharging.defaultschanged"
    /// The agent applies a new target at its next evaluation, about once a minute.
    public static let settleTime: TimeInterval = 150

    /// The agent's own values before the helper first wrote, so they can be put back.
    public struct Originals: Codable, Equatable, Sendable {
        public var featureState: Int?
        public var limit: Int?
        public init(featureState: Int?, limit: Int?) {
            self.featureState = featureState
            self.limit = limit
        }
    }
}

/// Whether a target written to macOS's limit took. A target macOS does not report within the
/// settle time, when none ever did, means this Mac does not take such targets: the helper stops
/// writing instead of trying again every minute.
public struct NativeLimitWatch: Codable, Equatable, Sendable {
    public private(set) var written: Int?
    public private(set) var writtenAt: Date?
    /// macOS has reported a target the helper wrote at least once.
    public private(set) var confirmed = false
    public private(set) var failed = false

    public init() {}

    /// Takes in what macOS reports now.
    public mutating func observe(_ reported: Int?, now: Date) {
        guard let written, let writtenAt else { return }
        if reported == written {
            confirmed = true
        } else if !confirmed, now.timeIntervalSince(writtenAt) > NativeChargeLimit.settleTime {
            failed = true
        }
    }

    /// Whether `target` should be written now: not after a failure, not when macOS has it, and not
    /// again while the last write of it is still settling.
    public func shouldWrite(_ target: Int, reported: Int?, now: Date) -> Bool {
        guard !failed, reported != target else { return false }
        if written == target, let writtenAt, now.timeIntervalSince(writtenAt) <= NativeChargeLimit.settleTime { return false }
        return true
    }

    public mutating func wrote(_ target: Int, at now: Date) {
        written = target
        writtenAt = now
    }
}
