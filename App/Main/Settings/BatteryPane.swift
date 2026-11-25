import SwiftUI
import ToolsmithKit

struct BatteryPane: View {
    @ObservedObject var charge: ChargeController

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xxl) {
            SettingsLead(text: String(localized: "A battery lasts longer when it is not always kept at 100%. Charging stops at the limit and the adapter powers the Mac from then on, so the battery neither charges nor runs down. It runs down only when you choose Discharge."))
            if charge.canControl {
                SettingsSection(title: String(localized: "Charge Limit"), footer: note) {
                    ContentRow { ChargeControls(charge: charge) }
                    if let snapshot = charge.snapshot, snapshot.abilities.canHold, snapshot.conflicts.isEmpty {
                        PickerRow(title: String(localized: "Sailing Range"),
                                  detail: String(localized: "How far the battery may fall below the limit before it charges again"),
                                  selection: Binding(get: { snapshot.sailing }, set: { charge.setSailing($0) }),
                                  options: ChargeLimit.sailingChoices) { String(localized: "\($0) points") }
                    }
                }
            }
            SettingsSection(title: String(localized: "Helper"), footer: String(localized: "Charging is controlled by a small helper inside \(AppIdentity.name) that runs with administrator rights: macOS’s own charge limit alone runs a battery above it down to it and takes only a few values. Click Install and the helper is registered as a background item of the system; once you allow it in System Settings → General → Login Items, it runs. It does nothing but charging, takes requests only from \(AppIdentity.name), and writes nothing while another charge app runs. Click Remove to put charging and macOS’s charge limit back as they were and delete it.")) {
                SettingsRow(title: stateTitle, detail: stateDetail) {
                    actions
                }
            }
        }
        .onAppear { charge.refresh() }
    }

    @ViewBuilder private var actions: some View {
        switch charge.state {
        case .notInstalled:
            RowButton(String(localized: "Install")) { charge.install() }
        case .needsApproval:
            RowButton(String(localized: "Open Login Items")) { charge.openLoginItems() }
            RowButton(String(localized: "Check Again")) { charge.refresh() }
        case .outdated:
            RowButton(String(localized: "Update")) { charge.updateHelper() }.disabled(charge.busy)
            RowButton(String(localized: "Remove"), role: .destructive) { charge.uninstall() }.disabled(charge.busy)
        case .running, .unsupportedMac, .failed:
            RowButton(String(localized: "Remove"), role: .destructive) { charge.uninstall() }.disabled(charge.busy)
        case .unsupportedBuild, .noBattery:
            EmptyView()
        }
    }

    /// How this Mac keeps the limit.
    private var note: String? {
        guard let status = charge.status else { return nil }
        switch status.method {
        case .nativeLimit:
            return String(localized: "This Mac’s firmware takes limits only through macOS’s own charge limit, which the helper sets to the level to keep, so it is kept while the Mac sleeps. System Settings → Battery shows that value meanwhile.")
        case .some(.none):
            return String(localized: "This Mac’s power management chip can’t stop charging while the adapter powers the Mac, so a limit can’t be held; the battery charges to full. Discharge runs it down to the limit on request.")
        case .keys, nil:
            return nil
        }
    }

    private var stateTitle: String {
        switch charge.state {
        case .unsupportedBuild: return String(localized: "Not available in this build")
        case .noBattery: return String(localized: "This Mac has no battery")
        case .notInstalled: return String(localized: "Not installed")
        case .needsApproval: return String(localized: "Waiting for approval")
        case .running: return String(localized: "Running")
        case .outdated: return String(localized: "Needs updating")
        case .unsupportedMac: return String(localized: "This Mac is not supported")
        case .failed: return String(localized: "Something went wrong")
        }
    }

    private var stateDetail: String {
        switch charge.state {
        case .unsupportedBuild: return String(localized: "The helper installs only in release builds signed with the developer’s Developer ID")
        case .noBattery: return String(localized: "A charge limit only matters on a MacBook")
        case .notInstalled: return String(localized: "Installing asks once for an administrator password or approval")
        case .needsApproval: return String(localized: "Turn on \(AppIdentity.name) in System Settings → General → Login Items")
        case .running:
            return charge.snapshot.map { ChargeSummary.headline($0) } ?? ""
        case .outdated:
            return String(localized: "The installed helper is from an older version of \(AppIdentity.name). Until it is updated, charge control is off.")
        case .unsupportedMac: return String(localized: "No way to control charging was found in this Mac’s power management chip")
        case .failed(let message): return message
        }
    }
}
