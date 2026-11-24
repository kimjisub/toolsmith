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
                    SettingsSection(title: "단축키", footer: "줄을 누르고 원하는 키를 누릅니다. esc 는 취소, ⌫ 는 단축키 지우기입니다. 모든 단축키는 설정의 단축키에서 한눈에 봅니다.") {
                        ForEach(shortcuts) { HotkeyRow(environment: environment, action: $0) }
                    }
                }
                let needed = permissions.permissions.filter { kind in descriptor.permissions.contains { $0.rawValue == kind.kind.rawValue } }
                if !needed.isEmpty {
                    SettingsSection(title: "권한", footer: "허락하지 않아도 앱은 동작하고, 그 권한이 필요한 동작만 빠집니다.") {
                        ForEach(needed) { PermissionCard(permission: $0, granted: permissions.granted.contains($0.kind)) }
                    }
                }
            } else {
                Card {
                    EmptyState(symbol: descriptor.symbol, title: waitingFor.isEmpty ? "꺼져 있습니다" : "기다리는 기능이 꺼져 있습니다",
                               detail: "켜면 이 기능의 설정이 여기에 나옵니다. 꺼 둔 동안에도 쌓인 기록과 설정은 그대로 있습니다.")
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
