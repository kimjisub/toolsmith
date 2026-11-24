import AppKit
import SwiftUI
import ToolsmithKit

/// What the app keeps, where it goes, and the way to delete it. Everything is listed, nothing summarised.
struct PrivacyPane: View {
    @ObservedObject var environment: AppEnvironment
    @ObservedObject var modules: ModuleManager
    @ObservedObject var settings: SettingsStore
    @State private var sizes: [String: Int64] = [:]

    private static let folders: [(key: String, title: String, detail: String, pane: SettingsPane?)] = [
        ("clipboard", String(localized: "Clipboard History"), String(localized: "Text and images you copied. Copies marked as passwords and copies from apps you excluded are never kept"), .clipboard),
        ("screentime", String(localized: "Screen Time"), String(localized: "Which app was in front, and for how long. Deleted after 90 days"), .screenTime),
        ("monitor", String(localized: "System Monitor History"), String(localized: "One-minute averages of numbers like CPU, memory, network and power. Deleted after 28 days"), .monitor),
    ]

    var body: some View {
        SettingsPage(title: String(localized: "Privacy & Storage"), lead: String(localized: "Everything \(AppIdentity.name) keeps on this Mac and everything it sends out. Your history is never sent to any server.")) {
            SettingsSection(title: String(localized: "Kept on This Mac"), footer: String(localized: "All of it is in \((SettingsStore.supportDirectory.path as NSString).abbreviatingWithTildeInPath), readable only by you.")) {
                ForEach(Self.folders, id: \.key) { folder in
                    SettingsRow(title: folder.title, detail: "\(folder.detail) · \(ByteSize.text(Int(sizes[folder.key] ?? 0)))") {
                        // A switched-off feature has no page to manage it on; its data is still listed.
                        if let pane = folder.pane, case .module(let id) = pane, modules.isEnabled(id) {
                            RowButton(String(localized: "Manage")) { environment.settingsPane = pane }
                        }
                    }
                }
                SettingsRow(title: String(localized: "OpenRouter Key"), detail: KeyStore.hasSavedKey ? String(localized: "In this Mac’s keychain") : String(localized: "None")) {
                    if modules.isEnabled(AIModule.descriptor.id) { RowButton(String(localized: "Manage")) { environment.settingsPane = .ai } }
                }
                SettingsRow(title: String(localized: "Settings"), detail: String(localized: "Shortcuts and the choices on these screens")) {
                    RowButton(String(localized: "Show in Finder")) { NSWorkspace.shared.activateFileViewerSelecting([SettingsStore.supportDirectory]) }
                }
            }
            SettingsSection(title: String(localized: "Sent Out")) {
                SettingsRow(title: String(localized: "AI Answers → OpenRouter"), detail: String(localized: "Only when you ask the AI in the launcher, and only that question. Answers aren’t saved"))
                ToggleRow(title: String(localized: "Public IP Lookup → Cloudflare"), detail: String(localized: "Only when you open the network details, at most once every 5 minutes. Nothing about you is sent"),
                          isOn: settings.binding(\.publicAddressLookup))
                ToggleRow(title: String(localized: "Record Screen Time"), detail: String(localized: "Never sent. When off, the app in front isn’t recorded"), isOn: settings.moduleBinding(ScreenTimeModule.descriptor))
            }
        }
        .onAppear(perform: refresh)
    }

    private func refresh() {
        let base = SettingsStore.supportDirectory
        DispatchQueue.global(qos: .utility).async {
            var result: [String: Int64] = [:]
            for folder in Self.folders { result[folder.key] = DiskUsage.bytes(of: base.appendingPathComponent(folder.key, isDirectory: true)) }
            DispatchQueue.main.async { sizes = result }
        }
    }
}
