import Combine
import SwiftUI
import ToolsmithKit

/// Battery charging: the charge limit, held on the adapter, with discharge and a one-time full
/// charge on request. Switched off, its page, screen and timer go away; the limit macOS (or the
/// helper) already keeps stays as it was, since it is a setting of the Mac, not of this app.
@MainActor final class ChargeModule: AppModule {
    nonisolated static let screenID = "battery"
    nonisolated static let descriptor = ModuleDescriptor(
        id: screenID, title: String(localized: "Battery Charging"), summary: String(localized: "Stops charging at a limit like 80% and holds the battery there on the adapter"),
        symbol: "battery.100.bolt", tint: .green,
        menuBarItems: [MenuBarItemDescriptor(id: "battery.charge", moduleID: screenID, title: String(localized: "Battery Charge"), symbol: "battery.100.bolt",
                                             styles: [.iconAndValue, .icon], defaultVisible: false)])
    var descriptor: ModuleDescriptor { Self.descriptor }
    private unowned let host: ModuleHost
    /// Made when the module first starts: reading the charge state touches the system.
    private(set) var charge: ChargeController?
    /// The menu bar item's state, there before the module first starts and cleared when it stops.
    private let snapshots = CurrentValueSubject<ChargeSnapshot?, Never>(nil)
    private var relay: AnyCancellable?

    init(host: ModuleHost) { self.host = host }

    func settingsGroups(in environment: AppEnvironment) -> AnyView? {
        charge.map { AnyView(BatteryPane(charge: $0)) }
    }

    var panelScreens: [PanelScreen] {
        [PanelScreen(id: Self.screenID, title: String(localized: "Battery Charging"), symbol: Self.descriptor.symbol, settings: .module(Self.screenID),
                     content: { [weak self] in
                         guard let charge = self?.charge else { return AnyView(EmptyView()) }
                         return AnyView(ChargePanelScreen(charge: charge, openSettings: { [weak self] in self?.host.openSettings(.module(Self.screenID)) }))
                     })]
    }

    var menuBarItems: [MenuBarItem] {
        let changes = snapshots.map { _ in () }.eraseToAnyPublisher()
        return [MenuBarItem(descriptor: Self.descriptor.menuBarItems[0], glyph: { [snapshots] style in Self.glyph(snapshots.value, style: style) },
                            changes: changes, click: { [weak host] frame in host?.openPanel(Self.screenID, below: frame) })]
    }

    /// The activity's symbol; with the value, the level.
    private static func glyph(_ snapshot: ChargeSnapshot?, style: MenuBarStyle) -> MenuBarGlyph {
        guard let snapshot else { return MenuBarGlyph(pieces: [.symbol(descriptor.symbol)], spoken: descriptor.title) }
        let symbol = ChargeStateView.symbol(snapshot.activity)
        let spoken = ChargeSummary.headline(snapshot)
        guard style == .iconAndValue, let percent = snapshot.percent else { return MenuBarGlyph(pieces: [.symbol(symbol)], spoken: spoken) }
        return MenuBarGlyph(pieces: [.symbol(symbol), .text("\(percent)%")], spoken: spoken)
    }

    func start() {
        let charge = self.charge ?? ChargeController()
        self.charge = charge
        relay = charge.$snapshot.removeDuplicates().sink { [snapshots] in snapshots.send($0) }
        charge.start()
    }

    func stop() {
        charge?.stop()
        relay = nil
        snapshots.send(nil)
    }
}

/// The menu bar panel's battery screen: the charge state and its controls, or what is missing.
struct ChargePanelScreen: View {
    @ObservedObject var charge: ChargeController
    let openSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            if charge.canControl {
                ChargeControls(charge: charge)
            } else {
                Text(ChargePanelScreen.unavailable(charge.state)).font(.role(.secondary)).foregroundStyle(Ink.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                RowButton(String(localized: "Open Settings"), action: openSettings)
            }
        }
        .padding(Space.m)
    }

    static func unavailable(_ state: ChargeController.State) -> String {
        switch state {
        case .noBattery: return String(localized: "This Mac has no battery.")
        case .outdated: return String(localized: "The charge helper is older than this app. Update it in Settings → Battery Charging.")
        default: return String(localized: "Charge control needs the helper on this Mac. Set it up in Settings → Battery Charging.")
        }
    }
}
