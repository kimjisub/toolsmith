import Foundation

/// `toolsmith charge …`: the battery charging module's command line. Parsing and the report are
/// pure; the app runs them through the same controller the screens use.
public enum ChargeCommand: Equatable, Sendable {
    case status
    /// nil: no limit.
    case limit(Int?)
    case sailing(Int)
    case discharge(Bool)
    case topUp(Bool)
    case helperStatus
    /// `wait`: until the helper is allowed in Login Items, up to `ChargeCommand.approvalTimeout`.
    case helperInstall(wait: Bool)
    case helperUninstall

    public static let limitRange = 50...100
    public static let approvalTimeout: TimeInterval = 600

    public static let usage = """
    Usage: toolsmith charge <command> [--json]

      status                       What the battery is doing, the limit, the helper, other charge apps
      limit <50-100|off>           Charge limit (100 or off: charge to full)
      sailing <2|5|10|15|20>       Points under the limit before charging again
      discharge on|off             Run from the battery down to the limit while plugged in
      topup on|off                 Charge to 100% and keep it there until unplugged
      helper status                Whether the administrator helper is installed and running
      helper install [--wait]      Register the helper; macOS asks you to allow it in
                                   System Settings → General → Login Items (--wait: until you do)
      helper uninstall             Give charging and macOS's limit back, then remove the helper
    """

    public enum ParseError: Error, Equatable {
        case usage(String)
    }

    public static func parse(_ words: [String]) throws -> ChargeCommand {
        guard let verb = words.first else { return .status }
        let rest = Array(words.dropFirst())
        func one() throws -> String {
            guard rest.count == 1 else { throw ParseError.usage("\(verb) takes one value") }
            return rest[0].lowercased()
        }
        func onOff() throws -> Bool {
            switch try one() {
            case "on": return true
            case "off": return false
            default: throw ParseError.usage("\(verb) takes on or off")
            }
        }
        switch verb {
        case "status":
            guard rest.isEmpty else { throw ParseError.usage("status takes no value") }
            return .status
        case "limit":
            let value = try one()
            if value == "off" { return .limit(nil) }
            guard let percent = Int(value.trimmingCharacters(in: CharacterSet(charactersIn: "%"))), limitRange.contains(percent) else {
                throw ParseError.usage("limit takes \(limitRange.lowerBound)-\(limitRange.upperBound) or off")
            }
            return .limit(percent >= 100 ? nil : percent)
        case "sailing":
            guard let points = Int(try one()), ChargeLimit.sailingChoices.contains(points) else {
                throw ParseError.usage("sailing takes one of \(ChargeLimit.sailingChoices.map(String.init).joined(separator: ", "))")
            }
            return .sailing(points)
        case "discharge":
            return .discharge(try onOff())
        case "topup":
            return .topUp(try onOff())
        case "helper":
            switch rest.first {
            case "status" where rest.count == 1: return .helperStatus
            case "install" where rest.count == 1: return .helperInstall(wait: false)
            case "install" where rest == ["install", "--wait"]: return .helperInstall(wait: true)
            case "uninstall" where rest.count == 1: return .helperUninstall
            default: throw ParseError.usage("helper takes status, install [--wait] or uninstall")
            }
        default:
            throw ParseError.usage("unknown command: \(verb)")
        }
    }
}

/// What `toolsmith charge status` reports.
public struct ChargeReport: Codable, Equatable, Sendable {
    /// charging, holding, discharging, toppingUp, onBattery; nil while nothing controls the charge.
    public var activity: String?
    /// The state in words ("Sailing at 78%").
    public var summary: String?
    public var level: Int?
    public var onAdapter: Bool?
    public var limit: Int?
    public var sailing: Int?
    /// notInstalled, needsApproval, running, outdated, unsupportedMac, unsupportedBuild, noBattery, failed.
    public var helper: String
    public var helperDetail: String?
    public var method: String?
    public var systemLimit: Int?
    public var conflicts: [String]
    public var error: String?

    public init(activity: String? = nil, summary: String? = nil, level: Int? = nil, onAdapter: Bool? = nil, limit: Int? = nil,
                sailing: Int? = nil, helper: String, helperDetail: String? = nil, method: String? = nil, systemLimit: Int? = nil,
                conflicts: [String] = [], error: String? = nil) {
        self.activity = activity
        self.summary = summary
        self.level = level
        self.onAdapter = onAdapter
        self.limit = limit
        self.sailing = sailing
        self.helper = helper
        self.helperDetail = helperDetail
        self.method = method
        self.systemLimit = systemLimit
        self.conflicts = conflicts
        self.error = error
    }

    /// Lines of "label: value", for people.
    public var text: String {
        var lines: [String] = []
        if let summary { lines.append("state: \(summary)") }
        if let level { lines.append("battery: \(level)%\(onAdapter.map { $0 ? ", adapter connected" : ", on battery" } ?? "")") }
        if activity != nil {
            lines.append("limit: \(limit.map { "\($0)%" } ?? "off")")
            if let sailing { lines.append("sailing: \(sailing) points") }
        }
        lines.append("helper: \(helper)\(helperDetail.map { " (\($0))" } ?? "")")
        if let method { lines.append("method: \(method)") }
        if let systemLimit { lines.append("macOS limit: \(systemLimit)%") }
        if !conflicts.isEmpty { lines.append("other charge apps: \(conflicts.joined(separator: ", ")) (nothing is changed while they run)") }
        if let error { lines.append("error: \(error)") }
        return lines.joined(separator: "\n")
    }
}
