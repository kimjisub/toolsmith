import SwiftUI
import ToolsmithKit

/// Battery charging: the charge limit. Switched off, its page and controls go away; the limit macOS
/// (or the helper) already keeps stays as it was, since it is a setting of the Mac, not of this app.
@MainActor final class ChargeModule: AppModule {
    nonisolated static let descriptor = ModuleDescriptor(id: "battery", title: String(localized: "Battery Charging"), summary: String(localized: "Stops charging at a limit like 80% to spare the battery"),
                                             symbol: "battery.100.bolt", tint: .green)
    var descriptor: ModuleDescriptor { Self.descriptor }
    /// Made when the module first starts: reading the charge state touches the system.
    private(set) var charge: ChargeController?

    init(host: ModuleHost) {}

    func settingsGroups(in environment: AppEnvironment) -> AnyView? {
        charge.map { AnyView(BatteryPane(charge: $0)) }
    }

    func start() {
        if let charge { charge.refresh() } else { charge = ChargeController() }
    }

    func stop() {}
}
