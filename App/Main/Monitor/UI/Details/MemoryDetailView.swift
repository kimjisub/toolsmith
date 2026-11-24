import SwiftUI
import ToolsmithKit

struct MemoryDetailView: View {
    @ObservedObject var monitor: MonitorModel
    @ObservedObject var processes: ProcessMonitor
    @ObservedObject var selection: HistorySelection
    private var m: MemoryBreakdown { monitor.snapshot.memory }

    var body: some View {
        VStack(spacing: Space.s) {
            HistoryBlock(topic: .memoryUsed, selection: selection) {
                PanelHeader(title: String(localized: "Memory"), symbol: "memorychip")
                Figure(value: MonitorText.memory(m.used), caption: String(localized: "\(MonitorText.percent(m.usedPercent)) of \(MonitorText.memory(m.total)) used"))
                SplitBar(parts: [
                    .init(label: String(localized: "App"), value: MonitorText.memory(m.app), fraction: Double(m.app) / Double(max(m.total, 1)), color: MonitorStyle.primary),
                    .init(label: String(localized: "Wired Memory"), value: MonitorText.memory(m.wired), fraction: Double(m.wired) / Double(max(m.total, 1)), color: MonitorStyle.secondary),
                    .init(label: String(localized: "Compressed"), value: MonitorText.memory(m.compressed), fraction: Double(m.compressed) / Double(max(m.total, 1)), color: MonitorStyle.tertiary),
                ])
                TableRow(label: String(localized: "Free (including cached files)"), value: MonitorText.memory(m.free))
            }
            HistoryBlock(topic: .memoryPressure, selection: selection) {
                PanelHeader(title: String(localized: "Pressure"), symbol: "gauge.with.dots.needle.33percent")
                HStack(alignment: .center, spacing: Space.l) {
                    Figure(value: MonitorText.whole(m.pressure), unit: "%", caption: pressureText)
                    MeterBar(fraction: m.pressure / 100, fill: AnyShapeStyle(m.pressure < 50 ? MonitorStyle.tertiary : m.pressure < 80 ? MonitorStyle.secondary : MonitorStyle.hot))
                }
            }
            UsageList(title: String(localized: "Top Apps"), symbol: "list.number", entries: processes.memory, format: { MonitorText.memory(UInt64(max($0, 0))) })
            Panel {
                TableRow(label: String(localized: "Page Ins"), value: MonitorText.rate(monitor.snapshot.pageInRate))
                TableRow(label: String(localized: "Page Outs"), value: MonitorText.rate(monitor.snapshot.pageOutRate))
                TableRow(label: String(localized: "Swap"), value: MonitorText.memory(m.swapUsed))
            }
        }
    }

    private var pressureText: String {
        m.pressure < 50 ? String(localized: "Plenty") : m.pressure < 80 ? String(localized: "Tight, compressing and swapping") : String(localized: "Short, closing apps will speed things up")
    }
}
