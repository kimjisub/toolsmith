import SwiftUI
import ToolsmithKit

/// Settings → 기능: every feature on one line with its switch. A line of a feature that is on
/// opens its page.
struct FeaturesPane: View {
    @ObservedObject var environment: AppEnvironment
    @ObservedObject var modules: ModuleManager
    @ObservedObject var settings: SettingsStore

    var body: some View {
        SettingsPage(title: "기능", lead: "쓰는 기능만 켜 둡니다. 끈 기능은 백그라운드에서 아무것도 하지 않고, 권한을 묻지 않고, 단축키와 입력창 명령에서도 빠집니다. 켜면 바로 다시 살아납니다.") {
            SettingsSection(footer: "끈 기능의 기록과 설정은 지우지 않습니다. 다시 켜면 그대로 있습니다. 지우려면 개인정보와 저장 공간에서 지웁니다.") {
                ForEach(modules.descriptors) { row($0) }
            }
        }
    }

    /// One feature: its tile, name and a line, its switch, and the way to its page.
    private func row(_ module: ModuleDescriptor) -> some View {
        let switchedOn = settings.settings.modules.isOn(module)
        let running = modules.isEnabled(module.id)
        let missing = switchedOn ? ModuleResolver.missingRequirements(of: module, in: modules.descriptors, enabled: modules.enabled) : []
        return HStack(spacing: Space.m) {
            IconTile(symbol: module.symbol, color: module.tint.color, size: IconSize.tileLarge)
                .saturation(running || !switchedOn ? 1 : 0.2)
            VStack(alignment: .leading, spacing: Space.xs) {
                Text(module.title).font(.role(.body, weight: .medium))
                Text(detail(module, missing: missing))
                    .font(.role(.detail))
                    .foregroundStyle(missing.isEmpty ? Ink.tertiary : Brand.peach)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if module.canDisable {
                RowSwitch(title: module.title, isOn: settings.moduleBinding(module))
            } else {
                Badge(text: "항상 켜짐")
            }
            Image(systemName: "chevron.right").font(.role(.detail, weight: .semibold)).foregroundStyle(Ink.disabled).accessibilityHidden(true)
        }
        .padding(.horizontal, Space.l)
        .padding(.vertical, Space.m)
        .frame(minHeight: 52)
        .contentShape(Rectangle())
        .onTapGesture { environment.settingsPane = .module(module.id) }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }

    /// The line under the name: what it does and the permissions it asks for, or what it waits for.
    private func detail(_ module: ModuleDescriptor, missing: [ModuleDescriptor]) -> String {
        if !missing.isEmpty { return "먼저 \(missing.map { "「\($0.title)」" }.joined(separator: ", ")) 을 켜야 씁니다" }
        let permissions = module.permissions.map(\.title)
        return permissions.isEmpty ? module.summary : "\(module.summary) · \(permissions.joined(separator: ", ")) 권한"
    }
}

extension ModulePermission {
    var title: String {
        switch self {
        case .accessibility: return "손쉬운 사용"
        case .screenRecording: return "화면 기록"
        case .clipboard: return "다른 앱에서 붙여넣기"
        case .microphone: return "마이크"
        case .audioCapture: return "시스템 오디오 녹음"
        case .location: return "위치"
        }
    }
}
