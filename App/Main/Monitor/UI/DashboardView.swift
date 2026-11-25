import SwiftUI
import ToolsmithKit

/// What opens from the menu bar: the Mac at a glance, as a list in the launcher's style. Each row is
/// one part of the Mac with its headline number and a short curve; pointing at a row lights it and
/// opens its details beside the list (the panels follow the pointer; rows only report where they are).
struct DashboardView: View {
    @ObservedObject var monitor: MonitorModel
    var onRowFrame: (MonitorSection, CGRect) -> Void

    private var s: SystemSnapshot { monitor.snapshot }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            VStack(spacing: Space.xs) {
                row(.cpu, symbol: "cpu", title: "CPU", value: MonitorText.whole(s.cpu.total), unit: "%",
                    detail: [s.cpuMHz.map(MonitorText.frequency), s.temperatures.cpu.map(MonitorText.temperature)].compactMap { $0 }.joined(separator: " · ")) {
                    Sparkline(values: History.sum(monitor.cpuUserHistory, monitor.cpuSystemHistory), ceiling: 100)
                }
                row(.memory, symbol: "memorychip", title: String(localized: "Memory"), value: MonitorText.whole(s.memory.usedPercent), unit: "%",
                    detail: String(localized: "Pressure \(MonitorText.percent(s.memory.pressure)) · \(MonitorText.memory(s.memory.used))")) {
                    Sparkline(values: monitor.memoryHistory.values, ceiling: 100)
                }
                row(.sensors, symbol: "bolt", title: String(localized: "Power and Temperature"), value: s.power.system.map { MonitorText.whole($0) } ?? "-", unit: "W",
                    detail: [s.temperatures.cpu.map { "CPU " + MonitorText.temperature($0) }, fanText].compactMap { $0 }.joined(separator: " · ")) {
                    Sparkline(values: monitor.powerHistory.values)
                }
                row(.disk, symbol: "internaldrive", title: s.volume.name, value: ByteSize.text(Int(s.volume.available)), unit: String(localized: "free"),
                    detail: String(localized: "R \(MonitorText.rate(s.diskReadRate)) · W \(MonitorText.rate(s.diskWriteRate))")) {
                    MeterBar(fraction: s.volume.usedFraction).frame(width: 92)
                }
                row(.network, symbol: "arrow.up.arrow.down", title: String(localized: "Network Download"), value: MonitorText.rate(s.downloadRate), unit: "",
                    detail: String(localized: "Upload \(MonitorText.rate(s.uploadRate))")) {
                    DualSparkline(down: monitor.downloadHistory.values, up: monitor.uploadHistory.values)
                }
                if let battery = s.battery {
                    row(.battery, symbol: battery.isCharging ? "battery.100.bolt" : "battery.75", title: String(localized: "Battery"), value: MonitorText.whole(battery.level), unit: "%",
                        detail: [battery.isCharging ? String(localized: "Charging") : battery.onAdapter ? String(localized: "Plugged in") : String(localized: "On battery"), battery.health.map { String(localized: "Health \(MonitorText.percent($0))") }]
                            .compactMap { $0 }.joined(separator: " · ")) {
                        MeterBar(fraction: battery.level / 100, fill: AnyShapeStyle(battery.level < 20 ? MonitorStyle.hot : MonitorStyle.tertiary)).frame(width: 92)
                    }
                }
            }
            .padding(Space.s)
        }
        .frame(width: MonitorStyle.width)
        .foregroundStyle(Ink.primary)
    }

    private var fanText: String? {
        guard !s.fans.isEmpty else { return nil }
        let rpm = s.fans.map(\.rpm).filter(\.isFinite).max() ?? 0
        return rpm < 1 ? String(localized: "Fans stopped") : String(localized: "Fan \(MonitorText.whole(rpm)) rpm")
    }

    /// The Mac's name. A development build takes a stand-in after --mac-name, for screenshots.
    private static var macName: String {
        #if TOOLSMITH_DEV
        if let index = CommandLine.arguments.firstIndex(of: "--mac-name"), index + 1 < CommandLine.arguments.count {
            return CommandLine.arguments[index + 1]
        }
        #endif
        return Host.current().localizedName ?? String(localized: "This Mac")
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(Self.macName).font(.role(.emphasis, weight: .semibold)).lineLimit(1)
            Spacer()
            if s.uptime > 0 { Text("Up \(UptimeText.text(s.uptime))").font(.role(.detail)).foregroundStyle(MonitorStyle.quiet) }
        }
        .padding(.horizontal, Space.l)
        .padding(.top, Space.l)
        .padding(.bottom, Space.s)
    }

    private func row<Trailing: View>(_ section: MonitorSection, symbol: String, title: String, value: String, unit: String,
                                     detail: String, @ViewBuilder trailing: () -> Trailing) -> some View {
        let lit = monitor.detail == section
        let shape = RoundedRectangle(cornerRadius: Radius.m, style: .continuous)
        return HStack(spacing: Space.m) {
            Image(systemName: symbol)
                .font(.role(.body, weight: .medium))
                .foregroundStyle(lit ? Color.white : MonitorStyle.primary)
                .frame(width: 30, height: 30)
                .background((lit ? Tint.edge(MonitorStyle.primary) : Fill.card), in: RoundedRectangle(cornerRadius: Radius.s, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.role(.detail)).foregroundStyle(MonitorStyle.quiet).lineLimit(1)
                HStack(alignment: .firstTextBaseline, spacing: Space.xs) {
                    Text(value).font(.role(.title, weight: .medium, design: .rounded)).monospacedDigit().lineLimit(1)
                    if !unit.isEmpty { Text(unit).font(.role(.detail, design: .rounded)).foregroundStyle(MonitorStyle.quiet) }
                }
                if !detail.isEmpty { Text(detail).font(.role(.detail)).foregroundStyle(MonitorStyle.quiet).lineLimit(1).minimumScaleFactor(0.8) }
            }
            Spacer(minLength: Space.s)
            trailing().frame(width: 92, height: 30)
        }
        .padding(.horizontal, Space.m)
        .frame(height: 68)
        .background(lit ? Fill.selected : Color.clear, in: shape)
        .overlay(shape.strokeBorder(lit ? Tint.light(Brand.glow) : Color.clear, lineWidth: 1))
        .shadow(color: lit ? Tint.edge(Brand.glow) : .clear, radius: 8)
        .animation(.easeOut(duration: 0.12), value: lit)
        .contentShape(Rectangle())
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { onRowFrame(section, $0) }
    }
}
