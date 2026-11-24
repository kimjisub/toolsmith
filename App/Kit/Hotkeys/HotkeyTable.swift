import Foundation

public enum HotkeyID {
    public static let openLauncher = "launcher.open"
}

/// Which action each global shortcut runs. One key runs one action, and the launcher always has a key.
public struct HotkeyTable: Codable, Equatable {
    public static let launcherDefault = KeyCombo(keyCode: 49, modifiers: [.option])
    public static let defaults = HotkeyTable(bindings: [HotkeyID.openLauncher: launcherDefault])

    public private(set) var bindings: [String: KeyCombo]

    init(bindings: [String: KeyCombo]) { self.bindings = bindings }

    /// Reads a saved table, repairing what a hand-edited or damaged file could break:
    /// invalid combos and second owners of a key are dropped, and the launcher gets its key back.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let saved = try container.decodeIfPresent([String: KeyCombo].self, forKey: .bindings) ?? [:]
        var clean: [String: KeyCombo] = [:]
        var taken: Set<KeyCombo> = []
        // The launcher claims its key first; the rest in a stable order.
        let ids = saved.keys.sorted { ($0 != HotkeyID.openLauncher ? 1 : 0, $0) < ($1 != HotkeyID.openLauncher ? 1 : 0, $1) }
        for id in ids {
            guard let combo = saved[id], combo.isValid, !taken.contains(combo) else { continue }
            clean[id] = combo
            taken.insert(combo)
        }
        if clean[HotkeyID.openLauncher] == nil {
            for (id, combo) in clean where combo == Self.launcherDefault { clean[id] = nil }
            clean[HotkeyID.openLauncher] = Self.launcherDefault
        }
        bindings = clean
    }

    public func combo(for id: String) -> KeyCombo? { bindings[id] }

    public func owner(of combo: KeyCombo) -> String? {
        bindings.first { $0.value == combo }?.key
    }

    public enum AssignResult: Equatable {
        case assigned
        /// Another action already uses this key. The table is unchanged; `reassign` moves it.
        case taken(by: String)
        case invalid
    }

    public mutating func assign(_ combo: KeyCombo, to id: String) -> AssignResult {
        guard combo.isValid else { return .invalid }
        if let owner = owner(of: combo), owner != id { return .taken(by: owner) }
        bindings[id] = combo
        return .assigned
    }

    /// Takes the key from whichever action has it and gives it to `id`. The launcher's key
    /// cannot be taken, because the launcher must never be left without one.
    public mutating func reassign(_ combo: KeyCombo, to id: String) {
        guard combo.isValid else { return }
        if let owner = owner(of: combo), owner != id {
            guard owner != HotkeyID.openLauncher else { return }
            bindings[owner] = nil
        }
        bindings[id] = combo
    }

    /// Gives a new feature's actions their default shortcuts, once. An action already in
    /// `alreadySeeded` is skipped, so a shortcut the user removed stays removed. A default never
    /// takes a key that is in use and never replaces a key the user chose for that action.
    /// Returns the ids handled now, to be remembered.
    public mutating func seed(_ defaults: [String: KeyCombo], alreadySeeded: Set<String>) -> Set<String> {
        var handled: Set<String> = []
        for (id, combo) in defaults.sorted(by: { $0.key < $1.key }) where !alreadySeeded.contains(id) {
            handled.insert(id)
            guard bindings[id] == nil, combo.isValid, owner(of: combo) == nil else { continue }
            bindings[id] = combo
        }
        return handled
    }

    /// The table to hand to the system: without the bindings that start with `orphanPrefix` and
    /// belong to nothing in `live`. Such a key would be taken from every other app and do nothing.
    /// The saved table keeps them, so they work again if what they belong to comes back.
    /// The bindings worth registering with the system: those of commands that exist right now.
    /// A key of a switched-off feature, or of a snippet whose file could not be read, would take
    /// the key from every other app and do nothing. The bindings themselves stay in the table.
    public func registrable(live: Set<String>) -> HotkeyTable {
        HotkeyTable(bindings: bindings.filter { live.contains($0.key) })
    }

    public enum ClearError: Error { case launcherRequired }

    public mutating func clear(_ id: String) throws {
        guard id != HotkeyID.openLauncher else { throw ClearError.launcherRequired }
        bindings[id] = nil
    }
}
