import AppKit
import SwiftUI
import ToolsmithKit
import UniformTypeIdentifiers

struct ClipboardPane: View {
    let clipboard: ClipboardModule
    @ObservedObject var settings: SettingsStore
    @State private var stats: (count: Int, bytes: Int) = (0, 0)
    @State private var confirmingClear = false
    /// History this large is worth a mention. Nothing is deleted because of it.
    private static let largeBytes = 5_000_000_000
    /// Searching reads every entry; past this many it starts to lag behind typing (about 0.1 s a key).
    private static let manyItems = 20_000

    private var sizeNote: String? {
        if stats.count > Self.manyItems { return String(localized: "The history holds \(stats.count) items, which can slow down search. You can shorten how long items are kept, or clear it.") }
        if stats.bytes > Self.largeBytes { return String(localized: "The history has grown quite large. You can shorten how long items are kept, or clear it.") }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xxl) {
            SettingsLead(text: String(localized: "Press ⌥V to open the history strip, find something and paste it again. The history is never sent anywhere."))
            if !ClipboardMonitor.canRead {
                Notice(text: String(localized: "macOS is blocking what you copy in other apps. In System Settings → Privacy & Security → Paste from Other Apps, set \(AppIdentity.name) to Allow."))
            }
            SettingsSection(title: String(localized: "History"), footer: sizeNote) {
                ToggleRow(title: String(localized: "Pause History"), detail: String(localized: "While this is on, what you copy isn’t recorded"), isOn: settings.binding(\.clipboardPaused))
                PickerRow(title: String(localized: "Keep History"), detail: String(localized: "Pinned items stay regardless"), selection: Binding(get: { settings.settings.clipRetention }, set: { value in
                    settings.update { $0.clipRetention = value }
                    clipboard.purge()
                    refresh()
                }), options: ClipRetention.allCases, label: \.title)
                SettingsRow(title: String(localized: "Saved History"), detail: "\(String(localized: "\(stats.count) items")) · \(ByteSize.text(stats.bytes))") {
                    RowButton(String(localized: "Clear All…"), role: .destructive) { confirmingClear = true }
                }
            }
            SettingsSection(title: String(localized: "Apps Not Recorded"), footer: String(localized: "What you copy while one of these apps is in front, like a password manager, isn’t recorded. Copies marked as passwords are never recorded, whatever the app.")) {
                ForEach(settings.settings.clipIgnoredApps, id: \.self) { bundleID in
                    ListRow(icon: AppIconCache.icon(bundleID: bundleID), title: Self.name(of: bundleID), subtitle: bundleID,
                            removeLabel: String(localized: "Remove \(Self.name(of: bundleID))")) {
                        settings.update { $0.clipIgnoredApps.removeAll { $0 == bundleID } }
                    }
                }
                ActionsRow { RowButton(String(localized: "Add App…"), action: addApp) }
            }
        }
        .onAppear(perform: refresh)
        .confirmationDialog("Clear clipboard history?", isPresented: $confirmingClear) {
            Button("Clear All but Pinned", role: .destructive) { clipboard.clear(keepPinned: true); refresh() }
            Button("Clear Everything", role: .destructive) { clipboard.clear(keepPinned: false); refresh() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You can’t undo this.")
        }
    }

    private func refresh() { stats = clipboard.stats() }

    private static func name(of bundleID: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return bundleID }
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }

    private func addApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = true
        panel.prompt = String(localized: "Add")
        guard panel.runModal() == .OK else { return }
        let ids = panel.urls.compactMap { Bundle(url: $0)?.bundleIdentifier }
        settings.update { current in
            for id in ids where !current.clipIgnoredApps.contains(id) { current.clipIgnoredApps.append(id) }
        }
    }
}
