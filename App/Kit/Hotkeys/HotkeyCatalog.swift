import Foundation

/// An action the settings window can give a global shortcut to.
public struct HotkeyAction: Equatable, Identifiable {
    /// The key into `HotkeyTable`.
    public let id: String
    public let title: String
    public let group: String
    public let detail: String?

    public init(id: String, title: String, group: String, detail: String?) {
        self.id = id
        self.title = title
        self.group = group
        self.detail = detail
    }
}

public struct HotkeyGroup: Equatable {
    public let group: String
    public let actions: [HotkeyAction]
}

public enum HotkeyCatalog {
    public static let launcher = HotkeyAction(id: HotkeyID.openLauncher, title: localized("Open Launcher"), group: localized("General"),
                                              detail: localized("Brings up \(AppIdentity.name) from any app"))

    /// The launcher first, then every command that carries a `hotkeyID`. A feature that registers
    /// commands shows up here without touching the settings window.
    public static func actions(from commands: [Command]) -> [HotkeyAction] {
        [launcher] + commands.compactMap { command in
            command.hotkeyID.map { HotkeyAction(id: $0, title: command.title, group: command.section.title, detail: command.subtitle) }
        }
    }

    public static func filter(_ actions: [HotkeyAction], query: String) -> [HotkeyAction] {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return actions }
        return actions.filter { Matcher.score(query: query, candidate: $0.title) != nil }
    }

    /// Actions under their group titles, groups in the order they first appear.
    public static func grouped(_ actions: [HotkeyAction]) -> [HotkeyGroup] {
        var order: [String] = []
        var byGroup: [String: [HotkeyAction]] = [:]
        for action in actions {
            if byGroup[action.group] == nil { order.append(action.group) }
            byGroup[action.group, default: []].append(action)
        }
        return order.map { HotkeyGroup(group: $0, actions: byGroup[$0] ?? []) }
    }

    /// Something the user should know about a shortcut that is saved anyway.
    public enum Notice: Equatable {
        /// macOS itself uses this key.
        case systemShortcut
        /// The system refused the registration: another app holds the key.
        case registrationFailed
    }

    public static func notice(for combo: KeyCombo, id: String, system: Set<KeyCombo>, failed: [String: KeyCombo]) -> Notice? {
        if failed[id] == combo { return .registrationFailed }
        if system.contains(combo) { return .systemShortcut }
        return nil
    }
}
