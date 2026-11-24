import SwiftUI
import ToolsmithKit

/// Settings → Shortcuts: every global shortcut of the running features, in their groups.
struct HotkeysPane: View {
    @ObservedObject var environment: AppEnvironment
    @ObservedObject var settings: SettingsStore
    @State private var search = ""

    private var actions: [HotkeyAction] { HotkeyCatalog.actions(from: environment.engine.hotkeyCommands()) }

    var body: some View {
        let others = HotkeyCatalog.filter(actions.filter { $0.id != HotkeyID.openLauncher }, query: search)
        SettingsPage(title: String(localized: "Shortcuts"), lead: String(localized: "Click a row and press the keys you want. Esc cancels, ⌫ removes the shortcut. Shortcuts of features that are off aren’t listed and come back when you turn them on.")) {
            if environment.modules.isEnabled(LauncherModule.descriptor.id) {
                SettingsSection(title: String(localized: "Launcher"), footer: String(localized: "Everything else starts from the launcher, so this one can’t be empty.")) {
                    HotkeyRow(environment: environment, action: HotkeyCatalog.launcher)
                }
            }
            TextField("Search actions", text: $search).textFieldStyle(.roundedBorder)
            ForEach(HotkeyCatalog.grouped(others), id: \.group) { group in
                SettingsSection(title: group.group) {
                    ForEach(group.actions) { HotkeyRow(environment: environment, action: $0) }
                }
            }
            if others.isEmpty {
                Card { EmptyState(symbol: "command", title: search.isEmpty ? String(localized: "No actions can have a shortcut yet") : String(localized: "No Matching Actions")) }
            }
        }
        .onDisappear { environment.cancelRecording() }
    }
}

/// What a recorded key does to the shortcut table. Shared by every place that records one.
@MainActor enum HotkeyAssignment {
    enum Outcome {
        case done
        /// Why the key was not accepted.
        case message(String)
        /// The key belongs to another action: ask before moving it.
        case askMove(KeyCombo, HotkeyAction)
    }

    static func apply(_ key: RecordedKey, to id: String, settings: SettingsStore, actions: [HotkeyAction]) -> Outcome {
        switch key {
        case .cancel:
            return .done
        case .clear:
            do {
                try settings.updateHotkeys { try $0.clear(id) }
                return .done
            } catch {
                return .message(String(localized: "The launcher shortcut can’t be empty."))
            }
        case .combo(let combo):
            var copy = settings.settings.hotkeys
            switch copy.assign(combo, to: id) {
            case .assigned:
                settings.update { $0.hotkeys = copy }
                return .done
            case .invalid:
                return .message(String(localized: "Include ⌃, ⌥ or ⌘."))
            case .taken(let ownerID):
                if ownerID == HotkeyID.openLauncher {
                    return .message(String(localized: "\(combo.display) opens the launcher and can’t be moved."))
                } else if let owner = actions.first(where: { $0.id == ownerID }) {
                    return .askMove(combo, owner)
                }
                // The owner is an action that no longer exists: nothing to ask about.
                settings.update { $0.hotkeys.reassign(combo, to: id) }
                return .done
            }
        }
    }
}
