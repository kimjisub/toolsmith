import SwiftUI
import ToolsmithKit

struct DiskDetailView: View {
    @ObservedObject var monitor: MonitorModel
    @ObservedObject var selection: HistorySelection
    private var s: SystemSnapshot { monitor.snapshot }

    var body: some View {
        VStack(spacing: Space.s) {
            Panel {
                PanelHeader(title: s.volume.name, symbol: "internaldrive")
                Figure(value: ByteSize.text(Int(s.volume.available)), unit: String(localized: "available"), caption: String(localized: "Total \(ByteSize.text(Int(s.volume.total)))"))
                SplitBar(parts: [
                    .init(label: String(localized: "Used"), value: ByteSize.text(Int(max(0, s.volume.total - s.volume.available))), fraction: s.volume.usedFraction, color: MonitorStyle.primary),
                ])
            }
            HistoryBlock(topic: .disk, selection: selection) {
                PanelHeader(title: String(localized: "Reads and Writes"), symbol: "arrow.left.arrow.right")
                TableRow(label: String(localized: "Read"), value: MonitorText.rate(s.diskReadRate), dot: MonitorStyle.primary)
                TableRow(label: String(localized: "Write"), value: MonitorText.rate(s.diskWriteRate), dot: MonitorStyle.secondary)
            }
            let ssd = s.sensors.filter { $0.group == .ssd }
            if !ssd.isEmpty {
                Panel {
                    PanelHeader(title: String(localized: "Temperature"), symbol: "thermometer.medium")
                    ForEach(ssd) { HeatRow(label: $0.label, celsius: $0.celsius) }
                }
            }
        }
    }
}
