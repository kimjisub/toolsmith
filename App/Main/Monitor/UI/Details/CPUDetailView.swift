import SwiftUI
import ToolsmithKit

struct CPUDetailView: View {
    @ObservedObject var monitor: MonitorModel
    @ObservedObject var processes: ProcessMonitor
    @ObservedObject var selection: HistorySelection
    private var s: SystemSnapshot { monitor.snapshot }

    var body: some View {
        VStack(spacing: Space.s) {
            HistoryBlock(topic: .cpu, selection: selection) {
                PanelHeader(title: "CPU", symbol: "cpu")
                HStack(alignment: .bottom) {
                    Figure(value: MonitorText.whole(s.cpu.total), unit: "%",
                           caption: String(localized: "User \(MonitorText.percent(s.cpu.user)) · System \(MonitorText.percent(s.cpu.system))"))
                    Spacer()
                    Sparkline(values: zip(monitor.cpuUserHistory.values, monitor.cpuSystemHistory.values).map { $0 + $1 }, ceiling: 100)
                        .frame(width: 130, height: 40)
                }
            }
            if !s.cores.isEmpty { cores }
            UsageList(title: String(localized: "Top Apps"), symbol: "list.number", entries: processes.cpu, format: { String(format: "%.1f%%", $0) })
            HistoryBlock(topic: .gpu, selection: selection) {
                PanelHeader(title: "GPU", symbol: "square.stack.3d.up")
                Figure(value: s.gpu.map { MonitorText.whole($0) } ?? "-", unit: "%", caption: String(localized: "Graphics processor usage"))
                TableRow(label: String(localized: "Memory in use"), value: s.gpuMemory.map { MonitorText.memory($0) } ?? "-")
                TableRow(label: String(localized: "Temperature"), value: s.temperatures.gpu.map(MonitorText.temperature) ?? "-")
                TableRow(label: String(localized: "Frequency"), value: s.gpuMHz.map(MonitorText.frequency) ?? "-")
                if !processes.gpu.isEmpty {
                    Line.subtle.frame(height: 1)
                    ForEach(processes.gpu) { entry in
                        HStack(spacing: Space.s) {
                            AppIcon(path: entry.path).frame(width: 16, height: 16)
                            Text(entry.name).font(MonitorStyle.body).lineLimit(1)
                            Spacer()
                            Text(String(format: "%.1f%%", entry.value)).font(MonitorStyle.number)
                        }
                    }
                }
            }
            Panel {
                TableRow(label: String(localized: "Load average"), value: s.loadAverage.map { String(format: "%.2f", $0) }.joined(separator: "  "))
                    .help("Average number of tasks waiting to run over 1, 5 and 15 minutes")
                TableRow(label: String(localized: "Uptime"), value: UptimeText.text(s.uptime))
            }
        }
    }

    /// One bar per core, then each kind's clock and average.
    private var cores: some View {
        let colors = [MonitorStyle.primary, MonitorStyle.secondary, MonitorStyle.tertiary]
        return Panel {
            PanelHeader(title: String(localized: "\(s.cores.count) Cores"), symbol: "square.grid.3x3")
            CoreBars(values: s.cores, kinds: s.coreCluster).frame(height: 44)
            ForEach(Array(s.clusters.enumerated()), id: \.offset) { cluster, info in
                let usages = s.cores.indices.filter { $0 < s.coreCluster.count && s.coreCluster[$0] == cluster }.map { s.cores[$0] }
                let mhz = s.cpuClusterMHz[cluster == s.clusters.count - 1 && s.clusters.count > 1 ? "ECPU" : "PCPU"]
                TableRow(label: "\(info.label) \(info.count)" + (mhz.map { " · " + MonitorText.frequency(megahertz: $0) } ?? ""),
                          value: MonitorText.percent(usages.isEmpty ? 0 : usages.reduce(0, +) / Double(usages.count)), dot: colors[cluster % colors.count])
            }
        }
    }
}
