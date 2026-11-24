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
                }
            }
            if charge.state == .system {
                if charge.helperRegistered {
                    SettingsSection(title: String(localized: "Old Helper"), footer: String(localized: "This Mac uses macOS’s own charge limit, so the charge helper installed earlier is no longer needed. Removing it puts back the charge settings the helper changed, then deletes it.")) {
                        SettingsRow(title: String(localized: "Installed"), detail: String(localized: "No longer used")) {
                            RowButton(String(localized: "Remove"), role: .destructive) { charge.uninstall() }.disabled(charge.busy)
                        }
                    }
                }
            } else {
                SettingsSection(title: String(localized: "Helper"), footer: String(localized: "macOS on this Mac has no charge limit (Apple silicon Macs with macOS 26.4 or later do), so values are written directly to the Mac’s power management chip (SMC). That needs administrator rights. Click Install and a small helper inside \(AppIdentity.name) is registered as a background item of the system; once you allow it in System Settings → General → Login Items, it runs with administrator rights. The helper does nothing but charging and takes requests only from \(AppIdentity.name). Click Remove to put charging back as it was and delete it.")) {
                    SettingsRow(title: stateTitle, detail: stateDetail) {
                        actions
                    }
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
        case .unsupportedBuild, .noBattery, .system:
            EmptyView()
        }
    }

    /// How this Mac keeps the limit.
    private var note: String {
        if charge.state == .system {
            return String(localized: "Uses macOS’s own charge limit, kept by the firmware even while the Mac sleeps. When the battery is above your limit, \(AppIdentity.name) sets macOS’s limit to the battery’s level so it is held there instead of running down, and lowers it as the battery is used; System Settings → Battery shows that value meanwhile. macOS does not allow limits below 80%.")
        }
        guard let snapshot = charge.snapshot else { return "" }
        if snapshot.abilities.canHold {
            return String(localized: "Charging stops at the limit and starts again when the battery drops \(ChargePlanner.band) percentage points below it.")
        }
        return String(localized: "This Mac’s power management chip can’t stop charging while the adapter powers the Mac, so a limit can’t be held; the battery charges to full. Discharge runs it down to the limit on request.")
    }

    private var stateTitle: String {
        switch charge.state {
        case .system: return String(localized: "Not needed")
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
        case .system: return String(localized: "Uses macOS’s charge limit")
        case .unsupportedBuild: return String(localized: "The helper installs only in release builds signed with the developer’s Developer ID")
        case .noBattery: return String(localized: "A charge limit only matters on a MacBook")
        case .notInstalled: return String(localized: "Installing asks once for an administrator password or approval")
        case .needsApproval: return String(localized: "Turn on \(AppIdentity.name) in System Settings → General → Login Items")
        case .running:
            return charge.snapshot.map { ChargeSummary.headline($0) } ?? ""
        case .outdated:
            return String(localized: "The installed helper is from an older version of \(AppIdentity.name). Until it is updated, charge control is off; updating keeps the approval in Login Items.")
        case .unsupportedMac: return String(localized: "No way to control charging was found in this Mac’s power management chip")
        case .failed(let message): return message
        }
    }
}
