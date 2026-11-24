import SwiftUI
import ToolsmithKit

struct PermissionsPane: View {
    @ObservedObject var modules: ModuleManager
    @StateObject private var watcher = PermissionWatcher()

    var body: some View {
        SettingsPage(title: String(localized: "Permissions"), lead: String(localized: "What macOS lets you allow for each app. Features ask only for what they need when you first use them; here you can see and change everything at once.")) {
            // Only what the switched-on features use.
            let needed = Set(ModuleResolver.permissions(modules.descriptors, enabled: modules.enabled).map(\.rawValue))
            let permissions = watcher.permissions.filter { needed.contains($0.kind.rawValue) }
            if permissions.isEmpty {
                Text("None of the features you turned on need a permission.").font(.role(.secondary)).foregroundStyle(Ink.tertiary)
            }
            if permissions.contains(where: \.required) {
            SettingsSection(title: String(localized: "Required"), footer: String(localized: "Without it, window snapping and pasting directly don’t work. Everything else still works.")) {
                ForEach(permissions.filter(\.required)) { PermissionCard(permission: $0, granted: watcher.granted.contains($0.kind)) }
            }
            }
            if permissions.contains(where: { !$0.required }) {
            SettingsSection(title: String(localized: "Optional"), footer: String(localized: "The app works without them; only that feature is left out. To turn one off, go to System Settings → Privacy & Security.")) {
                ForEach(permissions.filter { !$0.required }) { PermissionCard(permission: $0, granted: watcher.granted.contains($0.kind)) }
            }
            }
        }
        .onAppear { watcher.start() }
        .onDisappear { watcher.stop() }
    }
}
