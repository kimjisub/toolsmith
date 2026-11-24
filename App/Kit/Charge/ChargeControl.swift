import Foundation

/// Battery charge control, shared by the app and its administrator helper. The helper does the
/// writing; everything here is pure so it can be tested.

/// The helper's identity, and the app's: each side of the XPC connection accepts only the other,
/// signed by the app's Developer ID team.
public enum ChargeHelperIdentity {
    public static let teamID = AppIdentity.teamID
    public static let appBundleID = AppIdentity.bundleID
    public static let helperBundleID = AppIdentity.helperBundleID
    /// launchd label, Mach service name and the plist's base name are all this.
    public static let machService = helperBundleID
    public static let plistName = "\(helperBundleID).plist"
    /// Bumped when the helper's vocabulary changes; the app reinstalls an older helper.
    public static let version = 1

    /// A code signing requirement: Apple-anchored, this identifier, signed by our team.
    public static func requirement(identifier: String) -> String {
        "anchor apple generic and identifier \"\(identifier)\" and certificate leaf[subject.OU] = \"\(teamID)\""
    }
}

/// How this Mac's charge controller is told what to do. The keys differ by firmware; the helper
/// asks which exist and never writes one that does not.
///
/// From the open-source `battery` CLI (actuallymentor/battery), which tests each key by reading it:
/// - Stop charging: `CHTE` (4 bytes, 01000000 stop / 00000000 charge) on newer Apple silicon
///   firmware; otherwise `CH0B` and `CH0C` together (1 byte, 02 stop / 00 charge).
/// - Run from the battery although plugged in (adapter off): `CHIE` (08 / 00), else `CH0J`, else
///   `CH0I` (01 / 00).
public struct ChargeKeys: Equatable, Sendable {
    public struct Write: Equatable, Sendable {
        public let key: String
        public let on: [UInt8]
        public let off: [UInt8]
    }

    /// Writes that stop charging (all of them, in order), or empty when the Mac has none.
    public let inhibit: [Write]
    /// The write that takes the Mac off the adapter, or nil.
    public let adapter: Write?

    public init(present keys: Set<String>) {
        if keys.contains("CHTE") {
            inhibit = [Write(key: "CHTE", on: [0x01, 0x00, 0x00, 0x00], off: [0x00, 0x00, 0x00, 0x00])]
        } else if keys.contains("CH0B"), keys.contains("CH0C") {
            inhibit = [Write(key: "CH0B", on: [0x02], off: [0x00]), Write(key: "CH0C", on: [0x02], off: [0x00])]
        } else {
            inhibit = []
        }
        if keys.contains("CHIE") {
            adapter = Write(key: "CHIE", on: [0x08], off: [0x00])
        } else if keys.contains("CH0J") {
            adapter = Write(key: "CH0J", on: [0x01], off: [0x00])
        } else if keys.contains("CH0I") {
            adapter = Write(key: "CH0I", on: [0x01], off: [0x00])
        } else {
            adapter = nil
        }
    }

    /// The keys worth asking the controller about.
    public static let candidates: Set<String> = ["CHTE", "CH0B", "CH0C", "CHIE", "CH0J", "CH0I"]

    public var canPause: Bool { !inhibit.isEmpty }
    public var canDischarge: Bool { adapter != nil }
    /// A limit can be held by stopping the charge, or, without that, by leaving the adapter.
    public var canLimit: Bool { canPause || canDischarge }
}

/// What the user asked for. Saved by the helper so it holds across restarts.
public struct ChargeSettings: Codable, Equatable, Sendable {
    /// 50…100, or nil for no limit.
    public var limit: Int?
    public var paused = false
    public var discharging = false

    public init(limit: Int? = nil, paused: Bool = false, discharging: Bool = false) {
        self.limit = ChargeLimit.clamp(limit)
        self.paused = paused
        self.discharging = discharging
    }

    public static let defaults = ChargeSettings()
}

public enum ChargeLimit {
    public static let range = 50...100
    /// How far under the limit the level must fall before charging starts again, so the
    /// controller is not switched at every percent. Holding by leaving the adapter drains the
    /// battery, so that band is wider: fewer, longer cycles.
    public static let hysteresis = 2.0
    public static let adapterHysteresis = 5.0

    public static func hysteresis(for keys: ChargeKeys) -> Double {
        keys.canPause ? hysteresis : adapterHysteresis
    }
    /// Below this the battery always charges and the adapter always stays on, whatever was asked.
    public static let safetyFloor = 15.0

    /// A limit as sent over the wire: nil, 0 or 100 and above mean "no limit".
    public static func clamp(_ value: Int?) -> Int? {
        guard let value, value > 0, value < 100 else { return nil }
        return min(max(value, range.lowerBound), range.upperBound)
    }
}

/// What the controller should be doing now.
public struct ChargeOutput: Equatable, Sendable {
    public var inhibit: Bool
    public var adapterOff: Bool

    public init(inhibit: Bool, adapterOff: Bool) {
        self.inhibit = inhibit
        self.adapterOff = adapterOff
    }

    /// Charging enabled, adapter on: the Mac as Apple ships it.
    public static let normal = ChargeOutput(inhibit: false, adapterOff: false)
}

public enum ChargeDecision {
    /// The next state, from the battery level (0…100), the settings, what the Mac can do, and the
    /// current state (kept between the limit and the hysteresis band below it).
    public static func decide(level: Double, settings: ChargeSettings, keys: ChargeKeys, current: ChargeOutput) -> ChargeOutput {
        guard level.isFinite, level > ChargeLimit.safetyFloor else { return .normal }
        var holding = false
        if let limit = settings.limit.map(Double.init) {
            let wasHolding = keys.canPause ? current.inhibit : current.adapterOff
            if level >= limit {
                holding = true
            } else if level > limit - ChargeLimit.hysteresis(for: keys) {
                holding = wasHolding
            }
        }
        let discharging = settings.discharging && !dischargeDone(level: level, settings: settings)
        // Without a way to stop the charge, a limit is held by running from the battery.
        let inhibit = keys.canPause && (settings.paused || holding)
        let adapterOff = keys.canDischarge && (discharging || (holding && !keys.canPause))
        return ChargeOutput(inhibit: inhibit, adapterOff: adapterOff)
    }

    /// Discharging runs the battery down to the limit (or, with no limit, to the safety floor) and
    /// then ends by itself.
    public static func dischargeDone(level: Double, settings: ChargeSettings) -> Bool {
        level <= Double(settings.limit ?? 0) || level <= ChargeLimit.safetyFloor
    }

    /// Before the Mac sleeps nothing watches the level, so the adapter goes back on (a stopped
    /// charge is safe to keep: the battery cannot overfill or drain because of it).
    public static func forSleep(_ output: ChargeOutput) -> ChargeOutput {
        ChargeOutput(inhibit: output.inhibit, adapterOff: false)
    }
}

/// The helper's report, sent to the app as JSON.
public struct ChargeStatus: Codable, Equatable, Sendable {
    public var version: Int
    public var settings: ChargeSettings
    public var output: ChargeOutput
    public var canPause: Bool
    public var canDischarge: Bool
    public var level: Double?
    /// Why the last write failed, if it did.
    public var error: String?

    public init(version: Int = ChargeHelperIdentity.version, settings: ChargeSettings, output: ChargeOutput,
                canPause: Bool, canDischarge: Bool, level: Double?, error: String? = nil) {
        self.version = version
        self.settings = settings
        self.output = output
        self.canPause = canPause
        self.canDischarge = canDischarge
        self.level = level
        self.error = error
    }
}

extension ChargeOutput: Codable {}

/// The helper's whole vocabulary over XPC. Replies carry a JSON-encoded `ChargeStatus`.
@objc public protocol ChargeHelperProtocol {
    func status(reply: @escaping (Data) -> Void)
    /// 0 turns the limit off; other values are clamped to 50…100.
    func setLimit(_ percent: Int, reply: @escaping (Data) -> Void)
    func setPaused(_ paused: Bool, reply: @escaping (Data) -> Void)
    func setDischarging(_ discharging: Bool, reply: @escaping (Data) -> Void)
    /// Charging on, adapter on, no limit: as Apple ships the Mac.
    func restoreDefaults(reply: @escaping (Data) -> Void)
}
