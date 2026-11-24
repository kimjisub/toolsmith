import Foundation

/// The user's on/off choice per module. A module the user never touched follows its default, so a
/// module added in a later version starts the way it was designed to.
public struct ModuleSwitches: Codable, Equatable, Sendable {
    public private(set) var choices: [String: Bool]

    public init(_ choices: [String: Bool] = [:]) { self.choices = choices }

    public init(from decoder: Decoder) throws {
        choices = try decoder.singleValueContainer().decode([String: Bool].self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(choices)
    }

    /// The switch as the user left it (requirements are not considered).
    public func isOn(_ module: ModuleDescriptor) -> Bool {
        guard module.canDisable else { return true }
        return choices[module.id] ?? module.defaultEnabled
    }

    public mutating func set(_ module: ModuleDescriptor, on: Bool) {
        guard module.canDisable else { return }
        choices[module.id] = on
    }
}

/// Which modules actually run: switched on, and everything they require running too.
public enum ModuleResolver {
    public static func enabled(_ modules: [ModuleDescriptor], switches: ModuleSwitches) -> Set<String> {
        let byID = Dictionary(modules.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var on = Set(modules.filter(switches.isOn).map(\.id))
        // Drop modules whose requirement is off or unknown until nothing changes (chains, A → B → C).
        while true {
            let next = on.filter { id in byID[id]?.requires.allSatisfy(on.contains) ?? false }
            if next == on { return on }
            on = next
        }
    }

    /// The requirements that keep a switched-on module from running, by title, in declared order.
    public static func missingRequirements(of module: ModuleDescriptor, in modules: [ModuleDescriptor], enabled: Set<String>) -> [ModuleDescriptor] {
        module.requires.compactMap { id in enabled.contains(id) ? nil : modules.first { $0.id == id } }
    }

    /// The permissions the running modules need, in a fixed order.
    public static func permissions(_ modules: [ModuleDescriptor], enabled: Set<String>) -> [ModulePermission] {
        let needed = Set(modules.filter { enabled.contains($0.id) }.flatMap(\.permissions))
        return ModulePermission.allCases.filter(needed.contains)
    }
}
