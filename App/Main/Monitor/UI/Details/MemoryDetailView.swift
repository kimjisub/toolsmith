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
                PanelHeader(title: "메모리", symbol: "memorychip")
                Figure(value: MonitorText.memory(m.used), caption: "\(MonitorText.memory(m.total)) 중 \(MonitorText.percent(m.usedPercent)) 사용")
                SplitBar(parts: [
                    .init(label: "앱", value: MonitorText.memory(m.app), fraction: Double(m.app) / Double(max(m.total, 1)), color: MonitorStyle.primary),
                    .init(label: "와이어드", value: MonitorText.memory(m.wired), fraction: Double(m.wired) / Double(max(m.total, 1)), color: MonitorStyle.secondary),
                    .init(label: "압축됨", value: MonitorText.memory(m.compressed), fraction: Double(m.compressed) / Double(max(m.total, 1)), color: MonitorStyle.tertiary),
                ])
                TableRow(label: "여유 (캐시된 파일 포함)", value: MonitorText.memory(m.free))
            }
            HistoryBlock(topic: .memoryPressure, selection: selection) {
                PanelHeader(title: "압력", symbol: "gauge.with.dots.needle.33percent")
                HStack(alignment: .center, spacing: Space.l) {
                    Figure(value: MonitorText.whole(m.pressure), unit: "%", caption: pressureText)
                    MeterBar(fraction: m.pressure / 100, fill: AnyShapeStyle(m.pressure < 50 ? MonitorStyle.tertiary : m.pressure < 80 ? MonitorStyle.secondary : MonitorStyle.hot))
                }
            }
            UsageList(title: "많이 쓰는 앱", symbol: "list.number", entries: processes.memory, format: { MonitorText.memory(UInt64(max($0, 0))) })
            Panel {
                TableRow(label: "페이지 입력", value: MonitorText.rate(monitor.snapshot.pageInRate))
                TableRow(label: "페이지 출력", value: MonitorText.rate(monitor.snapshot.pageOutRate))
                TableRow(label: "스왑", value: MonitorText.memory(m.swapUsed))
            }
        }
    }

    private var pressureText: String {
        m.pressure < 50 ? "여유 있음" : m.pressure < 80 ? "빠듯함, 압축과 스왑을 쓰는 중" : "부족함, 앱을 닫으면 빨라집니다"
    }
}
