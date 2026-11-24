import SwiftUI
import ToolsmithKit

/// Every module's settings page, in one shape: the module header with its switch, the module's
/// own groups, its shortcuts, its permissions. A switched-off module shows only its header.
struct ModuleSettingsScreen: View {
    @ObservedObject var environment: AppEnvironment
    @ObservedObject var modules: ModuleManager
    @ObservedObject var settings: SettingsStore
    let module: AppModule
    @StateObject private var permissions = PermissionWatcher()

    private var descriptor: ModuleDescriptor { module.descriptor }
    private var running: Bool { modules.isEnabled(descriptor.id) }

    var body: some View {
        SettingsScroll {
            ModuleHeader(module: descriptor, isOn: settings.moduleBinding(descriptor), waitingFor: waitingFor)
            if running {
                if let groups = module.settingsGroups(in: environment) { groups }
                let shortcuts = shortcutActions
                if !shortcuts.isEmpty {
                    SettingsSection(title: String(localized: "Shortcuts"), footer: String(localized: "Click a row and press the keys you want. Esc cancels, ⌫ removes the shortcut. Settings → Shortcuts lists every shortcut at once.")) {
                        ForEach(shortcuts) { HotkeyRow(environment: environment, action: $0) }
                    }
                }
                let needed = permissions.permissions.filter { kind in descriptor.permissions.contains { $0.rawValue == kind.kind.rawValue } }
                if !needed.isEmpty {
                    SettingsSection(title: String(localized: "Permissions"), footer: String(localized: "The app works without them; only what needs the permission is left out.")) {
                        ForEach(needed) { PermissionCard(permission: $0, granted: permissions.granted.contains($0.kind)) }
                    }
                }
            } else {
                Card {
                    EmptyState(symbol: descriptor.symbol, title: waitingFor.isEmpty ? String(localized: "Turned Off") : String(localized: "A feature this one needs is off"),
                               detail: String(localized: "Turn it on to see its settings here. Its history and settings are kept while it’s off."))
                }
            }
        }
        .onAppear { permissions.start() }
        .onDisappear { permissions.stop() }
    }

    /// The modules a switched-on module waits for, by title.
    private var waitingFor: [String] {
        guard settings.settings.modules.isOn(descriptor), !running else { return [] }
        return ModuleResolver.missingRequirements(of: descriptor, in: modules.descriptors, enabled: modules.enabled).map(\.title)
    }

    /// The module's shortcuts: those it handles itself, then its commands', in their order.
    private var shortcutActions: [HotkeyAction] {
        let own = module.hotkeyIDs.contains(HotkeyID.openLauncher) ? [HotkeyCatalog.launcher] : []
        let commands = HotkeyCatalog.actions(from: module.commandSources.flatMap { $0.commands() }).filter { $0.id != HotkeyID.openLauncher }
        let all = own + commands
        guard let ids = module.settingsShortcutIDs else { return all }
        return ids.compactMap { id in all.first { $0.id == id } }
    }
}
