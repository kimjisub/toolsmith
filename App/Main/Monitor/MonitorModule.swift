import AppKit
import Combine
import SwiftUI
import ToolsmithKit

/// System monitor: CPU, memory, power, temperatures, disk, network and battery, in the menu bar
/// and in the dashboard under it. Switched off, nothing is read and no history is written.
@MainActor final class MonitorModule: AppModule {
    nonisolated static let descriptor = ModuleDescriptor(
        id: "monitor", title: String(localized: "System Monitor"), summary: String(localized: "See CPU, memory, power, temperature and network in the menu bar and a dashboard"),
        symbol: "gauge.with.dots.needle.67percent", tint: .orange, permissions: [.location],
        menuBarItems: MonitorMenuBar.Reading.allCases.map(\.descriptor))
    var descriptor: ModuleDescriptor { Self.descriptor }
    private unowned let host: ModuleHost
    let monitor = MonitorModel()
    let fan = FanController()
    let panels: MonitorPanels

    init(host: ModuleHost) {
        self.host = host
        panels = MonitorPanels(monitor: monitor, fan: fan,
                               charge: { [weak host] in host?.module(ChargeModule.self)?.charge },
                               openSettings: { [weak host] pane in
                                   host?.closePanel()
                                   host?.openSettings(pane)
                               })
        monitor.allowsPublicAddressLookup = { [weak host] in host?.settings.settings.publicAddressLookup ?? false }
    }

    var appMenuItems: [AppMenuEntry] {
        [AppMenuEntry(title: String(localized: "System Monitor"), symbol: "gauge.with.dots.needle.67percent") { [weak self] in self?.open(section: nil, below: nil) }]
    }

    var menuBarItems: [MenuBarItem] {
        let changes = monitor.$snapshot.map { _ in () }.eraseToAnyPublisher()
        return MonitorMenuBar.Reading.allCases.map { reading in
            MenuBarItem(descriptor: reading.descriptor,
                        glyph: { [monitor] style in MonitorMenuBar.glyph(reading, style: style, monitor: monitor) },
                        changes: changes,
                        click: { [weak self] frame in self?.open(section: reading.section, below: frame) })
        }
    }

    func settingsGroups(in environment: AppEnvironment) -> AnyView? {
        AnyView(MonitorPane(environment: environment, monitor: monitor, settings: environment.settings))
    }

    static let screenID = "monitor"

    var panelScreens: [PanelScreen] {
        [PanelScreen(id: Self.screenID, title: String(localized: "System Monitor"), symbol: Self.descriptor.symbol, width: MonitorStyle.width,
                     settings: .monitor, content: { [panels] in panels.dashboard() },
                     onShow: { [weak self] window in
                         guard let self else { return }
                         self.panels.attach(to: window)
                         if let section = self.pendingSection { self.panels.open(section) }
                         self.pendingSection = nil
                     },
                     onHide: { [weak self] in self?.panels.detach() },
                     auxiliaryWindows: { [weak self] in self?.panels.sideWindows ?? [] })]
    }

    func start() { monitor.start() }

    func stop() {
        panels.detach()
        monitor.stop()
        fan.shutdown()
    }

    func menuBarItemsShown(_ ids: Set<String>) { monitor.meterShown = !ids.isEmpty }

    /// A section to open as soon as the dashboard is on screen.
    private var pendingSection: MonitorSection?

    /// Opens the panel on the dashboard (or closes it when the dashboard is showing), with a section's details.
    func open(section: MonitorSection?, below anchor: NSRect?) {
        pendingSection = section
        host.openPanel(Self.screenID, below: anchor)
    }
}

/// The monitor's menu bar readings and how each style draws them.
enum MonitorMenuBar {
    enum Reading: String, CaseIterable {
        case cpu, memory, disk, network, battery, readout

        var section: MonitorSection {
            switch self {
            case .cpu: return .cpu
            case .memory: return .memory
            case .disk: return .disk
            case .network: return .network
            case .battery: return .battery
            case .readout: return .sensors
            }
        }

        var descriptor: MenuBarItemDescriptor {
            let graphs: [MenuBarStyle] = [.graph, .iconAndValue, .value]
            switch self {
            case .cpu: return item(String(localized: "CPU Usage"), "cpu", graphs)
            case .memory: return item(String(localized: "Memory Usage"), "memorychip", graphs)
            case .disk: return item(String(localized: "Disk Reads and Writes"), "internaldrive", graphs)
            case .network: return item(String(localized: "Network Speed"), "arrow.up.arrow.down", graphs)
            case .battery: return item(String(localized: "Battery"), "battery.75percent", graphs)
            case .readout: return item(String(localized: "CPU Temperature and Power"), "thermometer.medium", [.value, .iconAndValue])
            }
        }

        private func item(_ title: String, _ symbol: String, _ styles: [MenuBarStyle]) -> MenuBarItemDescriptor {
            MenuBarItemDescriptor(id: "monitor.\(rawValue)", moduleID: "monitor", title: title, symbol: symbol, styles: styles, defaultVisible: true)
        }
    }

    static let barCount = MenuBarRenderer.barCount

    @MainActor static func glyph(_ reading: Reading, style: MenuBarStyle, monitor: MonitorModel) -> MenuBarGlyph? {
        let s = monitor.snapshot
        func recent(_ history: History) -> [Double] { Array(history.values.suffix(barCount)) }
        /// `floor` (bytes a second) is the least a full bar stands for, so idle chatter stays low.
        func scaled(_ a: [Double], _ b: [Double], floor: Double) -> ([Double], [Double]) {
            // One scale for both directions, so a busy one and an idle one look like that.
            let top = max((a + b).max() ?? 1, floor)
            return (a.map { $0 / top }, b.map { $0 / top })
        }
        /// The value pieces, with the item's symbol in front for `.iconAndValue`.
        func value(_ pieces: [MenuBarPiece], spoken: String) -> MenuBarGlyph {
            MenuBarGlyph(pieces: (style == .iconAndValue ? [.symbol(reading.descriptor.symbol)] : []) + pieces, spoken: spoken)
        }
        switch reading {
        case .cpu:
            let spoken = "CPU \(MonitorText.percent(s.cpu.total))"
            guard style == .graph else { return value([.text(MonitorText.percent(s.cpu.total))], spoken: spoken) }
            return MenuBarGlyph(pieces: [.label("CPU"), .bars(lower: recent(monitor.cpuUserHistory).map { $0 / 100 },
                                                               upper: recent(monitor.cpuSystemHistory).map { $0 / 100 })], spoken: spoken)
        case .memory:
            let spoken = String(localized: "Memory \(MonitorText.percent(s.memory.usedPercent))")
            guard style == .graph else { return value([.text(MonitorText.percent(s.memory.usedPercent))], spoken: spoken) }
            return MenuBarGlyph(pieces: [.label("MEM"), .level(s.memory.usedPercent / 100, MenuBarRenderer.blue)], spoken: spoken)
        case .disk:
            let spoken = String(localized: "Disk read \(MonitorText.rate(s.diskReadRate)), write \(MonitorText.rate(s.diskWriteRate))")
            guard style == .graph else { return value([.stack(MonitorText.rate(s.diskReadRate), MonitorText.rate(s.diskWriteRate))], spoken: spoken) }
            let (r, w) = scaled(recent(monitor.diskReadHistory), recent(monitor.diskWriteHistory), floor: 1_048_576)
            return MenuBarGlyph(pieces: [.label("SSD"), .mirror(above: r, below: w, aboveColor: MenuBarRenderer.blue, belowColor: MenuBarRenderer.red)], spoken: spoken)
        case .network:
            let spoken = String(localized: "Upload \(MonitorText.rate(s.uploadRate)), download \(MonitorText.rate(s.downloadRate))")
            guard style == .graph else { return value([.stack("↑" + MonitorText.rate(s.uploadRate), "↓" + MonitorText.rate(s.downloadRate))], spoken: spoken) }
            let (u, d) = scaled(recent(monitor.uploadHistory), recent(monitor.downloadHistory), floor: 262_144)
            return MenuBarGlyph(pieces: [.label("NET"), .mirror(above: u, below: d, aboveColor: MenuBarRenderer.red, belowColor: MenuBarRenderer.blue)], spoken: spoken)
        case .battery:
            guard let battery = s.battery else { return nil }
            let spoken = String(localized: "Battery \(MonitorText.percent(battery.level))")
            guard style == .graph else { return value([.text(MonitorText.percent(battery.level))], spoken: spoken) }
            return MenuBarGlyph(pieces: [.label("BAT"), .level(battery.level / 100, battery.level < 20 ? MenuBarRenderer.red : MenuBarRenderer.green)], spoken: spoken)
        case .readout:
            guard let temperature = s.temperatures.cpu else { return nil }
            let watts = s.power.system.map { MonitorText.whole($0) + "W" }
            return value([.stack(MonitorText.temperature(temperature), watts ?? "")],
                         spoken: s.power.system.map { String(localized: "CPU \(MonitorText.temperature(temperature)), power \(MonitorText.watts($0))") } ?? "CPU \(MonitorText.temperature(temperature))")
        }
    }
}
