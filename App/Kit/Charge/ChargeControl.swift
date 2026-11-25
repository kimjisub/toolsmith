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
    /// Bumped when the helper's vocabulary changes; the app offers to update an older helper.
    /// 2: sails and holds instead of leaving the adapter, drives macOS's own limit where the keys are
    /// gone, `setTopUp` and `setSailing` replaced `setPaused`.
    /// 3: macOS's limit read from powerd and lifted through the agent for a charge to 100%.
    public static let version = 3

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
}

/// What the user asked for. Saved by the helper so it holds across restarts.
public struct ChargeSettings: Codable, Equatable, Sendable {
    /// 20…99, or nil for no limit.
    public var limit: Int?
    /// How far under the limit the battery may fall before it charges again.
    public var sailing = ChargeLimit.defaultSailing
    public var discharging = false
    public var toppingUp = false

    public init(limit: Int? = nil, sailing: Int = ChargeLimit.defaultSailing, discharging: Bool = false, toppingUp: Bool = false) {
        self.limit = ChargeLimit.clamp(limit)
        self.sailing = ChargeLimit.clampSailing(sailing)
        self.discharging = discharging
        self.toppingUp = toppingUp
    }

    public static let defaults = ChargeSettings()

    /// The one-off in effect; a top-up wins over a discharge.
    public var request: ChargeRequest {
        get { toppingUp ? .topUp : discharging ? .discharge : .none }
        set {
            toppingUp = newValue == .topUp
            discharging = newValue == .discharge
        }
    }

    private enum CodingKeys: String, CodingKey { case limit, sailing, discharging, toppingUp }

    /// Files from helper version 1 have only `limit` and `discharging` (and a `paused` no longer used).
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(limit: try container.decodeIfPresent(Int.self, forKey: .limit),
                  sailing: try container.decodeIfPresent(Int.self, forKey: .sailing) ?? ChargeLimit.defaultSailing,
                  discharging: try container.decodeIfPresent(Bool.self, forKey: .discharging) ?? false,
                  toppingUp: try container.decodeIfPresent(Bool.self, forKey: .toppingUp) ?? false)
    }
}

public enum ChargeLimit {
    public static let range = 20...100
    /// The limits offered; 100 stands for none.
    public static let choices = [50, 60, 70, 75, 80, 85, 90, 95, 100]
    /// Below this the battery always charges and the adapter always stays on, whatever was asked.
    public static let safetyFloor = 15.0
    /// AlDente's suggestion (5 to 10 points): charging resumes only after a real drop, not at every
    /// percent the Mac uses.
    public static let defaultSailing = 5
    public static let sailingRange = 1...20
    public static let sailingChoices = [2, 5, 10, 15, 20]

    /// A limit as sent over the wire: nil, 0 or 100 and above mean "no limit".
    public static func clamp(_ value: Int?) -> Int? {
        guard let value, value > 0, value < 100 else { return nil }
        return min(max(value, range.lowerBound), range.upperBound)
    }

    public static func clampSailing(_ value: Int) -> Int {
        min(max(value, sailingRange.lowerBound), sailingRange.upperBound)
    }
}

/// How the helper controls charging on this Mac.
public enum ChargeMethod: String, Codable, Equatable, Sendable {
    /// The charge controller's own keys stop charging (firmware before macOS 26.7 / 27).
    case keys
    /// macOS's own charge limit, set to any percentage through PowerUIAgent's preferences.
    case nativeLimit
    /// Neither: only discharging (adapter off) is possible, or nothing.
    case none
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
    /// What the battery is doing; nil from a helper older than version 2.
    public var activity: ChargeActivity?
    public var method: ChargeMethod?
    /// The target last handed to macOS's limit, and what macOS reports now.
    public var target: Int?
    public var systemLimit: Int?
    /// Other charge-control apps running now (by name). While there are any, the helper writes nothing.
    public var conflicts: [String]?

    public init(version: Int = ChargeHelperIdentity.version, settings: ChargeSettings, output: ChargeOutput,
                canPause: Bool, canDischarge: Bool, level: Double?, error: String? = nil, activity: ChargeActivity? = nil,
                method: ChargeMethod? = nil, target: Int? = nil, systemLimit: Int? = nil, conflicts: [String]? = nil) {
        self.version = version
        self.settings = settings
        self.output = output
        self.canPause = canPause
        self.canDischarge = canDischarge
        self.level = level
        self.error = error
        self.activity = activity
        self.method = method
        self.target = target
        self.systemLimit = systemLimit
        self.conflicts = conflicts
    }

    public var abilities: ChargeAbilities { ChargeAbilities(canHold: canPause, canDischarge: canDischarge) }
}

extension ChargeOutput: Codable {}

/// The helper's whole vocabulary over XPC. Replies carry a JSON-encoded `ChargeStatus`.
@objc public protocol ChargeHelperProtocol {
    func status(reply: @escaping (Data) -> Void)
    /// 0 turns the limit off; other values are clamped to 20…99.
    func setLimit(_ percent: Int, reply: @escaping (Data) -> Void)
    /// Points under the limit the battery may fall before charging again (1…20). Version 2.
    func setSailing(_ points: Int, reply: @escaping (Data) -> Void)
    func setDischarging(_ discharging: Bool, reply: @escaping (Data) -> Void)
    /// Charges to 100% and keeps it there until unplugged. Version 2.
    func setTopUp(_ toppingUp: Bool, reply: @escaping (Data) -> Void)
    /// Charging on, adapter on, macOS's limit as it was before the helper: as the user left the Mac.
    func restoreDefaults(reply: @escaping (Data) -> Void)
}
