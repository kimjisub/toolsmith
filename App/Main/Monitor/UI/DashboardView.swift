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
                    Sparkline(values: zip(monitor.cpuUserHistory.values, monitor.cpuSystemHistory.values).map { $0 + $1 }, ceiling: 100)
                }
                row(.memory, symbol: "memorychip", title: "메모리", value: MonitorText.whole(s.memory.usedPercent), unit: "%",
                    detail: "압력 \(MonitorText.percent(s.memory.pressure)) · \(MonitorText.memory(s.memory.used)) 사용") {
                    Sparkline(values: monitor.memoryHistory.values, ceiling: 100)
                }
                row(.sensors, symbol: "bolt", title: "전력과 온도", value: s.power.system.map { MonitorText.whole($0) } ?? "-", unit: "W",
                    detail: [s.temperatures.cpu.map { "CPU " + MonitorText.temperature($0) }, fanText].compactMap { $0 }.joined(separator: " · ")) {
                    Sparkline(values: monitor.powerHistory.values)
                }
                row(.disk, symbol: "internaldrive", title: s.volume.name, value: ByteSize.text(Int(s.volume.available)), unit: "남음",
                    detail: "읽기 \(MonitorText.rate(s.diskReadRate)) · 쓰기 \(MonitorText.rate(s.diskWriteRate))") {
                    MeterBar(fraction: s.volume.usedFraction).frame(width: 92)
                }
                row(.network, symbol: "arrow.up.arrow.down", title: "네트워크 다운로드", value: MonitorText.rate(s.downloadRate), unit: "",
                    detail: "업로드 \(MonitorText.rate(s.uploadRate))") {
                    DualSparkline(down: monitor.downloadHistory.values, up: monitor.uploadHistory.values)
                }
                if let battery = s.battery {
                    row(.battery, symbol: battery.isCharging ? "battery.100.bolt" : "battery.75", title: "배터리", value: MonitorText.whole(battery.level), unit: "%",
                        detail: [battery.isCharging ? "충전 중" : battery.onAdapter ? "어댑터 연결됨" : "배터리 사용 중", battery.health.map { "건강 " + MonitorText.percent($0) }]
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
        return rpm < 1 ? "팬 멈춤" : "팬 \(MonitorText.whole(rpm)) rpm"
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(Host.current().localizedName ?? "이 맥").font(.role(.emphasis, weight: .semibold)).lineLimit(1)
            Spacer()
            if s.uptime > 0 { Text("가동 시간 \(UptimeText.text(s.uptime))").font(.role(.detail)).foregroundStyle(MonitorStyle.quiet) }
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
                if !detail.isEmpty { Text(detail).font(.role(.detail)).foregroundStyle(MonitorStyle.quiet).lineLimit(1) }
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
