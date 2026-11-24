import SwiftUI
import ToolsmithKit

struct SensorsDetailView: View {
    @ObservedObject var monitor: MonitorModel
    @ObservedObject var fan: FanController
    @ObservedObject var selection: HistorySelection
    @State private var expanded: Set<SensorGroup> = []
    private var s: SystemSnapshot { monitor.snapshot }

    var body: some View {
        VStack(spacing: Space.s) {
            HistoryBlock(topic: .power, selection: selection) {
                PanelHeader(title: "전력", symbol: "bolt")
                Figure(value: s.power.system.map { MonitorText.whole($0) } ?? "-", unit: "W", caption: "맥 전체가 지금 쓰는 전력")
                PowerFlow(power: s.power)
            }
            HistoryBlock(topic: .cpuTemperature, selection: selection) {
                PanelHeader(title: "온도", symbol: "thermometer.medium")
                if s.sensors.isEmpty {
                    Text("온도 센서를 읽을 수 없습니다").font(.role(.secondary)).foregroundStyle(MonitorStyle.quiet)
                }
                ForEach(SensorCatalog.summaries(s.sensors)) { summary in
                    SensorGroupRow(summary: summary, expanded: expanded.contains(summary.group)) {
                        if expanded.contains(summary.group) { expanded.remove(summary.group) } else { expanded.insert(summary.group) }
                    }
                }
            }
            if !s.fans.isEmpty {
                Panel {
                    PanelHeader(title: "팬", symbol: "fan")
                    ForEach(s.fans) { reading in
                        HStack(spacing: Space.s) {
                            Text(s.fans.count == 2 ? (reading.index == 0 ? "왼쪽" : "오른쪽") : "팬 \(reading.index + 1)").font(MonitorStyle.body)
                                .foregroundStyle(Ink.secondary)
                            Spacer()
                            MeterBar(fraction: reading.fraction, height: 4).frame(width: 54)
                            Text(reading.rpm < 1 ? "멈춤" : "\(MonitorText.whole(reading.rpm)) rpm").font(MonitorStyle.number).frame(width: 76, alignment: .trailing)
                        }
                    }
                    #if TOOLSMITH_DEV
                    FanControls(fan: fan, fans: s.fans)
                    #endif
                }
            }
        }
    }
}

/// A group's hottest temperature with its heat bar; opens to every sensor in it.
private struct SensorGroupRow: View {
    let summary: SensorSummary
    let expanded: Bool
    let toggle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Button(action: toggle) {
                HStack(spacing: Space.s) {
                    Image(systemName: "chevron.right").font(.role(.caption, weight: .bold)).rotationEffect(.degrees(expanded ? 90 : 0))
                        .foregroundStyle(MonitorStyle.quiet).opacity(summary.readings.count > 1 ? 1 : 0)
                    HeatRow(label: summary.name, celsius: summary.peak,
                            note: summary.readings.count > 1 ? "평균 \(MonitorText.temperature(summary.average))" : nil)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(summary.readings.count < 2)
            .help(summary.readings.count > 1 ? "센서 \(summary.readings.count)개 중 가장 뜨거운 값" : "")
            if expanded {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: Space.xs) {
                    ForEach(summary.readings) { reading in
                        Text(MonitorText.temperature(reading.celsius)).font(.role(.detail, design: .rounded)).monospacedDigit()
                            .foregroundStyle(MonitorStyle.heat(reading.celsius))
                            .help(reading.key)
                    }
                }
                .padding(.leading, Space.l)
            }
        }
    }
}

#if TOOLSMITH_DEV
/// Automatic, or held at a chosen point between each fan's slowest and fastest. Development
/// builds only: the helper that sets the speed runs as root (see the repository's CLAUDE.md).
private struct FanControls: View {
    @ObservedObject var fan: FanController
    let fans: [FanReading]

    var body: some View {
        Line.subtle.frame(height: 1)
        HStack(spacing: Space.s) {
            Segmented(title: "팬", selection: Binding(get: { fan.mode == .manual },
                                                    set: { manual in if manual { fan.applyManual(fans: fans) } else { fan.returnToAutomatic() } }),
                      options: [false, true], label: { $0 ? "직접" : "자동" })
            .frame(width: 110)
            .disabled(fan.isBusy)
            if fan.isBusy {
                Spinner()
            } else if fan.mode == .manual {
                Slider(value: $fan.fraction, in: 0...1) { editing in if !editing { fan.applyManual(fans: fans) } }
                Text((MonitorText.whole((fan.fraction * 100)) + "%")).font(MonitorStyle.number).frame(width: 38, alignment: .trailing)
            }
        }
        if let message = fan.message {
            Text(message).font(.role(.detail)).foregroundStyle(Status.warning).fixedSize(horizontal: false, vertical: true)
        } else if fan.mode == .manual {
            Text("앱을 끄거나 \(Int(FanLimits.emergencyTemperature))° 를 넘으면 자동으로 돌아갑니다").font(.role(.detail)).foregroundStyle(Ink.tertiary)
        }
    }
}
#endif
