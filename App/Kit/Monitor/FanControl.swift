import Foundation

/// What the app may ask the root helper to do. Nothing else is understood: the helper runs as
/// root, so its whole vocabulary is these three lines.
public enum FanCommand: Equatable, Sendable {
    /// Hold a fan at a speed (the helper clamps it to the fan's own range).
    case set(fan: Int, rpm: Double)
    /// Give every fan back to the system.
    case auto
    case ping

    public static let maxFans = 8

    public init?(line: String) {
        guard line.utf8.count <= 64 else { return nil }
        let parts = line.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: " ", omittingEmptySubsequences: true)
        switch parts.first {
        case "auto" where parts.count == 1: self = .auto
        case "ping" where parts.count == 1: self = .ping
        case "set" where parts.count == 3:
            guard let fan = Int(parts[1]), (0..<Self.maxFans).contains(fan),
                  let rpm = Double(parts[2]), rpm.isFinite, rpm >= 0, rpm <= 20_000 else { return nil }
            self = .set(fan: fan, rpm: rpm)
        default: return nil
        }
    }

    public var line: String {
        switch self {
        case .set(let fan, let rpm): return "set \(fan) \(rpm)"
        case .auto: return "auto"
        case .ping: return "ping"
        }
    }
}

public enum FanLimits {
    /// At this core temperature the helper gives the fans back to the system, whatever was asked.
    public static let emergencyTemperature: Double = 95

    /// The speed to actually set: inside the fan's own slowest and fastest. nil when the range is
    /// unknown, in which case nothing is set.
    public static func clamp(_ rpm: Double, minimum: Double, maximum: Double) -> Double? {
        guard minimum > 0, maximum > minimum else { return nil }
        return min(max(rpm, minimum), maximum)
    }

    public static func rpm(fraction: Double, minimum: Double, maximum: Double) -> Double {
        (minimum + (maximum - minimum) * min(max(fraction, 0), 1)).rounded()
    }

    /// True when it is too hot, and also when there is no temperature to go by: a guard that
    /// cannot see must not let the fans be held.
    public static func mustReturnToAutomatic(hottestCore: Double?) -> Bool {
        guard let hottestCore else { return true }
        return hottestCore >= emergencyTemperature
    }
}

public enum FanHelperProtocol {
    /// The socket the helper listens on. Owned by the user who started it; no one else can connect.
    public static func socketPath(uid: UInt32) -> String { "/var/run/\(AppIdentity.bundleID).fan.\(uid).sock" }
}

public extension SMCValue {
    /// The bytes to write for a number, in the key's own type. nil when it does not fit.
    static func encode(type: String, value: Double) -> [UInt8]? {
        guard value.isFinite, value >= 0 else { return nil }
        switch type {
        case "flt ":
            let bits = Float(value).bitPattern
            return [UInt8(bits & 0xFF), UInt8(bits >> 8 & 0xFF), UInt8(bits >> 16 & 0xFF), UInt8(bits >> 24 & 0xFF)]
        case "fpe2":
            guard value <= 16_383 else { return nil }
            let raw = UInt16((value * 4).rounded())
            return [UInt8(raw >> 8), UInt8(raw & 0xFF)]
        case "ui8 ":
            guard value <= 255 else { return nil }
            return [UInt8(value.rounded())]
        case "ui16":
            guard value <= 65_535 else { return nil }
            let raw = UInt16(value.rounded())
            return [UInt8(raw >> 8), UInt8(raw & 0xFF)]
        default:
            return nil
        }
    }
}
