import SwiftUI
import ToolsmithKit

struct MonitorPane: View {
    @ObservedObject var environment: AppEnvironment
    let monitor: MonitorModel
    @ObservedObject var settings: SettingsStore
    @State private var historyBytes: Int64 = 0
    @State private var confirmingClear = false

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xxl) {
            SettingsLead(text: String(localized: "Click a value in the menu bar to open the dashboard. Hold the pointer over a card to open its details beside it."))
            SettingsSection(title: String(localized: "Menu Bar")) {
                SettingsRow(title: String(localized: "Values in the Menu Bar"), detail: String(localized: "Choose the order and style of CPU, memory, disk, network, battery, CPU temperature and power")) {
                    RowButton(String(localized: "Menu Bar Settings")) { environment.settingsPane = .menuBar }
                }
            }
            SettingsSection(title: String(localized: "Network"), footer: String(localized: "When on, opening the network details asks Cloudflare’s public address (www.cloudflare.com/cdn-cgi/trace) at most once every 5 minutes. Nothing is sent; Cloudflare sees this Mac’s public IP.")) {
                ToggleRow(title: String(localized: "Look Up Public IP Address"), detail: String(localized: "Shows the address and country the internet sees for this Mac"), isOn: settings.binding(\.publicAddressLookup))
            }
            SettingsSection(title: String(localized: "History"), footer: String(localized: "Kept on this Mac only, for 28 days: every reading of the last hour, then 1-minute averages (10-minute averages after 3 days). The graphs carry on after the app is reopened.")) {
                SettingsRow(title: String(localized: "Saved History"), detail: ByteSize.text(Int(historyBytes))) {
                    RowButton(String(localized: "Clear…"), role: .destructive) { confirmingClear = true }
                }
            }
        }
        .onAppear(perform: refresh)
        .confirmationDialog("Clear the system monitor history?", isPresented: $confirmingClear) {
            Button("Clear", role: .destructive) {
                monitor.clearHistory()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { refresh() }
            }
            Button("Cancel", role: .cancel) {}
        } message: { Text("The graphs’ past history will be removed. This can’t be undone.") }
    }

    private func refresh() {
        historyBytes = DiskUsage.bytes(of: SettingsStore.supportDirectory.appendingPathComponent("monitor", isDirectory: true))
    }
}

/// How much room a file or folder takes on disk.
enum DiskUsage {
    static func bytes(of url: URL) -> Int64 {
        let keys: Set<URLResourceKey> = [.totalFileAllocatedSizeKey, .isRegularFileKey]
        guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: Array(keys)) else {
            return Int64((try? url.resourceValues(forKeys: keys))?.totalFileAllocatedSize ?? 0)
        }
        var total: Int64 = 0
        for case let file as URL in enumerator {
            guard let values = try? file.resourceValues(forKeys: keys), values.isRegularFile == true else { continue }
            total += Int64(values.totalFileAllocatedSize ?? 0)
        }
        return total
    }
}
