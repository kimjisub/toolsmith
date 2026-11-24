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
                           caption: "사용자 \(MonitorText.percent(s.cpu.user)) · 시스템 \(MonitorText.percent(s.cpu.system))")
                    Spacer()
                    Sparkline(values: zip(monitor.cpuUserHistory.values, monitor.cpuSystemHistory.values).map { $0 + $1 }, ceiling: 100)
                        .frame(width: 130, height: 40)
                }
            }
            if !s.cores.isEmpty { cores }
            UsageList(title: "많이 쓰는 앱", symbol: "list.number", entries: processes.cpu, format: { String(format: "%.1f%%", $0) })
            HistoryBlock(topic: .gpu, selection: selection) {
                PanelHeader(title: "GPU", symbol: "square.stack.3d.up")
                Figure(value: s.gpu.map { MonitorText.whole($0) } ?? "-", unit: "%", caption: "그래픽 처리 장치 사용")
                TableRow(label: "쓰는 메모리", value: s.gpuMemory.map { MonitorText.memory($0) } ?? "-")
                TableRow(label: "온도", value: s.temperatures.gpu.map(MonitorText.temperature) ?? "-")
                TableRow(label: "주파수", value: s.gpuMHz.map(MonitorText.frequency) ?? "-")
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
                TableRow(label: "평균 부하", value: s.loadAverage.map { String(format: "%.2f", $0) }.joined(separator: "  "))
                    .help("1분, 5분, 15분 동안 실행을 기다린 작업 수의 평균")
                TableRow(label: "가동 시간", value: UptimeText.text(s.uptime))
            }
        }
    }

    /// One bar per core, then each kind's clock and average.
    private var cores: some View {
        let colors = [MonitorStyle.primary, MonitorStyle.secondary, MonitorStyle.tertiary]
        return Panel {
            PanelHeader(title: "코어 \(s.cores.count)개", symbol: "square.grid.3x3")
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
