import SwiftUI
import ToolsmithKit

/// 배터리 충전: the charge limit. Switched off, its page and controls go away; the limit macOS
/// (or the helper) already keeps stays as it was, since it is a setting of the Mac, not of this app.
@MainActor final class ChargeModule: AppModule {
    nonisolated static let descriptor = ModuleDescriptor(id: "battery", title: "배터리 충전", summary: "충전을 80% 같은 한도에서 멈춰 배터리를 아낍니다",
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
