import SwiftUI
import ToolsmithKit

/// Settings → Features: every feature on one line with its switch. A line of a feature that is on
/// opens its page.
struct FeaturesPane: View {
    @ObservedObject var environment: AppEnvironment
    @ObservedObject var modules: ModuleManager
    @ObservedObject var settings: SettingsStore

    var body: some View {
        SettingsPage(title: String(localized: "Features"), lead: String(localized: "Turn on only the features you use. A feature that is off does nothing in the background, asks for no permissions, and disappears from shortcuts and launcher commands. Turn it on and it’s back at once.")) {
            SettingsSection(footer: String(localized: "Turning a feature off doesn’t delete its history or settings; they’re still there when you turn it back on. To delete them, use Privacy & Storage.")) {
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
                Badge(text: String(localized: "Always On"))
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
        if !missing.isEmpty { return String(localized: "Turn on \(missing.map { String(localized: "“\($0.title)”") }.formatted(.list(type: .and).locale(.app))) first.") }
        let permissions = module.permissions.map(\.title)
        return permissions.isEmpty ? module.summary : String(localized: "\(module.summary) · Permissions: \(permissions.formatted(.list(type: .and).locale(.app)))")
    }
}

extension ModulePermission {
    var title: String {
        switch self {
        case .accessibility: return String(localized: "Accessibility")
        case .screenRecording: return String(localized: "Screen Recording")
        case .clipboard: return String(localized: "Paste from Other Apps")
        case .microphone: return String(localized: "Microphone")
        case .audioCapture: return String(localized: "System Audio Recording")
        case .location: return String(localized: "Location")
        }
    }
}
