import SwiftUI
import ToolsmithKit

struct PermissionsPane: View {
    @ObservedObject var modules: ModuleManager
    @StateObject private var watcher = PermissionWatcher()

    var body: some View {
        SettingsPage(title: "권한", lead: "macOS 가 앱마다 따로 허락하는 것들입니다. 기능은 처음 쓸 때 필요한 것만 묻고, 여기서 한눈에 보고 바꿀 수 있습니다.") {
            // Only what the switched-on features use.
            let needed = Set(ModuleResolver.permissions(modules.descriptors, enabled: modules.enabled).map(\.rawValue))
            let permissions = watcher.permissions.filter { needed.contains($0.kind.rawValue) }
            if permissions.isEmpty {
                Text("켜 둔 기능 중에 권한이 필요한 것이 없습니다.").font(.role(.secondary)).foregroundStyle(Ink.tertiary)
            }
            if permissions.contains(where: \.required) {
            SettingsSection(title: "필요", footer: "없으면 화면 나누기와 바로 붙여넣기가 동작하지 않습니다. 나머지 기능은 그대로 씁니다.") {
                ForEach(permissions.filter(\.required)) { PermissionCard(permission: $0, granted: watcher.granted.contains($0.kind)) }
            }
            }
            if permissions.contains(where: { !$0.required }) {
            SettingsSection(title: "선택", footer: "허락하지 않아도 앱은 동작하고, 그 기능만 빠집니다. 끄려면 시스템 설정 → 개인정보 보호 및 보안 에서 바꿉니다.") {
                ForEach(permissions.filter { !$0.required }) { PermissionCard(permission: $0, granted: watcher.granted.contains($0.kind)) }
            }
            }
        }
        .onAppear { watcher.start() }
        .onDisappear { watcher.stop() }
    }
}
