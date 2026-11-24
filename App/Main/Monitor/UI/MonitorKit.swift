import AppKit
import SwiftUI
import ToolsmithKit

/// The monitor speaks the launcher's language: dark glass, rows that light up under the pointer,
/// the lavender-to-peach gradient, and large plain numbers. Shapes are bars and curves, read left
/// to right; color marks meaning (heat, direction), not decoration.
enum MonitorStyle {
    static let primary = Brand.lavender
    static let secondary = Brand.peach
    static let tertiary = Brand.mint
    static let hot = Status.danger
    static let track = Fill.control
    static let quiet = Ink.tertiary
    static let width: CGFloat = 340
    static let label = Font.role(.detail, weight: .medium)
    static let body = Font.role(.body)
    static let number = Font.role(.body, design: .rounded).monospacedDigit()
    static let gradient = LinearGradient(colors: [primary, secondary], startPoint: .leading, endPoint: .trailing)

    /// Cool below 60°, warm below 85°, hot above.
    static func heat(_ celsius: Double) -> Color {
        celsius < 60 ? tertiary : celsius < 85 ? secondary : hot
    }
}

/// A thin bar filled from the left.
struct MeterBar: View {
    let fraction: Double
    var fill: AnyShapeStyle = AnyShapeStyle(MonitorStyle.gradient)
    var height: CGFloat = 5

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(MonitorStyle.track)
                Capsule().fill(fill).frame(width: max(height, proxy.size.width * Self.clamp(fraction)))
            }
        }
        .frame(height: height)
    }

    static func clamp(_ value: Double) -> Double { value.isFinite ? min(max(value, 0), 1) : 0 }
}

/// Parts of a whole as one bar cut into pieces, with a legend under it.
struct SplitBar: View {
    struct Part: Identifiable {
        let label: String
        let value: String
        let fraction: Double
        let color: Color
        var id: String { label }
    }

    let parts: [Part]

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            GeometryReader { proxy in
                HStack(spacing: Space.xs) {
                    ForEach(parts) { part in
                        RoundedRectangle(cornerRadius: Radius.xs, style: .continuous).fill(part.color)
                            .frame(width: max(2, (proxy.size.width - CGFloat(parts.count - 1) * 2) * MeterBar.clamp(part.fraction)))
                    }
                    Spacer(minLength: 0)
                }
                .background(RoundedRectangle(cornerRadius: Radius.xs, style: .continuous).fill(MonitorStyle.track))
            }
            .frame(height: 10)
            ForEach(parts) { TableRow(label: $0.label, value: $0.value, dot: $0.color) }
        }
    }
}

/// A smooth curve of recent values, faded underneath. nil values break the curve.
struct Sparkline: View {
    let values: [Double?]
    var ceiling: Double?
    var color: Color = MonitorStyle.primary
    var gradientStroke = true
    var filled = true

    var body: some View {
        Canvas { context, size in
            let known = values.compactMap { $0 }.filter(\.isFinite)
            guard values.count > 1, !known.isEmpty else { return }
            let top = max(ceiling ?? (known.max() ?? 1), 0.0001)
            let step = size.width / CGFloat(values.count - 1)
            var runs: [[CGPoint]] = [[]]
            for (index, value) in values.enumerated() {
                if let value, value.isFinite {
                    runs[runs.count - 1].append(CGPoint(x: CGFloat(index) * step, y: size.height * (1 - CGFloat(min(max(value / top, 0), 1)) * 0.92) - 1))
                } else if !runs[runs.count - 1].isEmpty {
                    runs.append([])
                }
            }
            for run in runs where !run.isEmpty {
                let line = Self.smooth(run)
                if filled {
                    var area = line
                    area.addLine(to: CGPoint(x: run.last!.x, y: size.height))
                    area.addLine(to: CGPoint(x: run[0].x, y: size.height))
                    area.closeSubpath()
                    context.fill(area, with: .linearGradient(Gradient(colors: [Tint.edge(color), color.opacity(0)]),
                                                             startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
                }
                let stroke: GraphicsContext.Shading = gradientStroke
                    ? .linearGradient(Gradient(colors: [color, MonitorStyle.secondary]), startPoint: .zero, endPoint: CGPoint(x: size.width, y: 0))
                    : .color(color)
                context.stroke(line, with: stroke, style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
            }
        }
    }

    /// Through every point, bending halfway between neighbours.
    static func smooth(_ points: [CGPoint]) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: first)
        if points.count == 1 {
            path.addLine(to: CGPoint(x: first.x + 1, y: first.y))
            return path
        }
        for index in 1..<points.count {
            let previous = points[index - 1], point = points[index]
            let mid = CGPoint(x: (previous.x + point.x) / 2, y: (previous.y + point.y) / 2)
            path.addQuadCurve(to: mid, control: previous)
            if index == points.count - 1 { path.addQuadCurve(to: point, control: point) }
        }
        return path
    }
}

/// Two curves on one scale: download in lavender, upload in peach.
struct DualSparkline: View {
    let down: [Double?]
    let up: [Double?]

    var body: some View {
        let top = max((down + up).compactMap { $0 }.max() ?? 1, 1)
        ZStack {
            Sparkline(values: down, ceiling: top, color: MonitorStyle.primary, gradientStroke: false)
            Sparkline(values: up, ceiling: top, color: MonitorStyle.secondary, gradientStroke: false, filled: false)
        }
    }
}

/// One bar per core, like a level meter; color says the kind of core.
struct CoreBars: View {
    let values: [Double]
    let kinds: [Int]

    var body: some View {
        let colors = [MonitorStyle.primary, MonitorStyle.secondary, MonitorStyle.tertiary]
        GeometryReader { proxy in
            HStack(alignment: .bottom, spacing: Space.xs) {
                ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                    ZStack(alignment: .bottom) {
                        RoundedRectangle(cornerRadius: Radius.xs, style: .continuous).fill(MonitorStyle.track)
                        RoundedRectangle(cornerRadius: Radius.xs, style: .continuous)
                            .fill(colors[(index < kinds.count ? kinds[index] : 0) % colors.count])
                            .frame(height: max(2, proxy.size.height * MeterBar.clamp(value / 100)))
                    }
                    .help("코어 \(index + 1): \(MonitorText.percent(value))")
                }
            }
        }
    }
}

/// A temperature with a short bar colored by how hot it is.
struct HeatRow: View {
    let label: String
    let celsius: Double
    var note: String?

    var body: some View {
        HStack(spacing: Space.s) {
            Text(label).font(MonitorStyle.body).foregroundStyle(Ink.secondary).lineLimit(1)
            if let note { Text(note).font(.role(.detail)).foregroundStyle(MonitorStyle.quiet).lineLimit(1) }
            Spacer(minLength: Space.s)
            MeterBar(fraction: celsius / 110, fill: AnyShapeStyle(MonitorStyle.heat(celsius)), height: 4).frame(width: 54)
            Text(MonitorText.temperature(celsius)).font(MonitorStyle.number).frame(width: 36, alignment: .trailing)
        }
    }
}

/// Apps ranked by one number: icon, name, value, and a faint bar for the share of the first.
struct UsageList: View {
    let title: String
    var symbol: String?
    let entries: [UsageEntry]
    let format: (Double) -> String
    var trailing: String?

    var body: some View {
        Panel {
            PanelHeader(title: title, symbol: symbol, trailing: trailing)
            if entries.isEmpty {
                Text("모으는 중…").font(.role(.secondary)).foregroundStyle(MonitorStyle.quiet)
            }
            let top = max(entries.first?.value ?? 1, 0.0001)
            ForEach(entries) { entry in
                HStack(spacing: Space.s) {
                    AppIcon(path: entry.path).frame(width: 18, height: 18)
                    VStack(alignment: .leading, spacing: Space.xs) {
                        HStack {
                            Text(entry.name).font(MonitorStyle.body).lineLimit(1).truncationMode(.middle)
                            Spacer(minLength: Space.s)
                            Text(format(entry.value)).font(MonitorStyle.number)
                        }
                        MeterBar(fraction: entry.value / top, fill: AnyShapeStyle(Tint.light(MonitorStyle.primary)), height: 2)
                    }
                }
            }
        }
    }
}

/// The icon of an app bundle or executable, cached.
struct AppIcon: View {
    let path: String?
    var body: some View { Image(nsImage: IconCache.shared.icon(for: path)).resizable().interpolation(.high) }
}

@MainActor final class IconCache {
    static let shared = IconCache()
    private var icons: [String: NSImage] = [:]
    private lazy var generic = NSWorkspace.shared.icon(for: .unixExecutable)

    func icon(for path: String?) -> NSImage {
        guard let path else { return generic }
        if let icon = icons[path] { return icon }
        let icon = path.hasSuffix(".app") ? NSWorkspace.shared.icon(forFile: path) : generic
        icons[path] = icon
        return icon
    }
}

// MARK: History, one level further

/// What a history view can show: the metrics, how to draw them and how to write a value.
enum HistoryTopic: String, Identifiable {
    case cpu, gpu, memoryUsed, memoryPressure, disk, network, power, cpuTemperature, batteryLevel, batteryTemperature
    var id: String { rawValue }

    var title: String {
        switch self {
        case .cpu: return "CPU 사용"
        case .gpu: return "GPU 사용"
        case .memoryUsed: return "메모리 사용"
        case .memoryPressure: return "메모리 압력"
        case .disk: return "디스크 읽기와 쓰기"
        case .network: return "네트워크"
        case .power: return "맥 전체 전력"
        case .cpuTemperature: return "CPU 온도"
        case .batteryLevel: return "배터리 잔량"
        case .batteryTemperature: return "배터리 온도"
        }
    }

    /// The first metric is drawn in lavender, the second (if any) in peach. CPU adds user and system.
    var metrics: [Metric] {
        switch self {
        case .cpu: return [.cpuUser, .cpuSystem]
        case .gpu: return [.gpu]
        case .memoryUsed: return [.memoryUsed]
        case .memoryPressure: return [.memoryPressure]
        case .disk: return [.diskRead, .diskWrite]
        case .network: return [.download, .upload]
        case .power: return [.systemPower]
        case .cpuTemperature: return [.cpuTemperature]
        case .batteryLevel: return [.batteryLevel]
        case .batteryTemperature: return [.batteryTemperature]
        }
    }

    var legend: [String] {
        switch self {
        case .disk: return ["읽기", "쓰기"]
        case .network: return ["다운로드", "업로드"]
        default: return []
        }
    }

    /// Whether the metrics are parts of one total (drawn as one summed curve).
    var sums: Bool { self == .cpu }
    var ceiling: Double? { [.cpu, .gpu, .memoryUsed, .memoryPressure, .batteryLevel].contains(self) ? 100 : nil }

    func format(_ value: Double) -> String {
        switch self {
        case .cpu, .gpu, .memoryUsed, .memoryPressure, .batteryLevel: return MonitorText.percent(value)
        case .disk, .network: return MonitorText.rate(value)
        case .power: return MonitorText.watts(value)
        case .cpuTemperature, .batteryTemperature: return MonitorText.temperature(value)
        }
    }
}

/// Where each block with a history sits in the details, so the panels can open its history when
/// the pointer is on it.
struct HistoryFrameKey: EnvironmentKey {
    static let defaultValue: ((HistoryTopic, CGRect) -> Void)? = nil
}

extension EnvironmentValues {
    var historyFrame: ((HistoryTopic, CGRect) -> Void)? {
        get { self[HistoryFrameKey.self] }
        set { self[HistoryFrameKey.self] = newValue }
    }
}

/// The topic whose history is showing, shared by the details (to light the block) and the history panel.
@MainActor final class HistorySelection: ObservableObject {
    @Published var topic: HistoryTopic?
}

/// A block with a history: pointing at it opens the history; a small mark says so.
struct HistoryBlock<Content: View>: View {
    let topic: HistoryTopic
    @ObservedObject var selection: HistorySelection
    @ViewBuilder var content: Content
    @Environment(\.historyFrame) private var report

    var body: some View {
        Panel(lit: selection.topic == topic) {
            content
        }
        .overlay(alignment: .topTrailing) {
            Image(systemName: "chart.xyaxis.line").font(.role(.caption, weight: .semibold))
                .foregroundStyle(selection.topic == topic ? Brand.glow : Tint.light(MonitorStyle.quiet))
                .padding(Space.m)
        }
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { report?(topic, $0) }
    }
}

/// The third level: one topic's history over a period picked with chips, with its low, average and high.
struct HistoryPanelView: View {
    @ObservedObject var monitor: MonitorModel
    @ObservedObject var selection: HistorySelection
    @AppStorage("monitor.historyRange") private var rangeValue = HistoryRange.oneHour.rawValue
    @State private var series: [Metric: [Double?]] = [:]

    static let ranges: [HistoryRange] = [.tenMinutes, .oneHour, .sixHours, .oneDay, .sevenDays, .twentyEightDays]
    private static let buckets = 120

    var body: some View {
        if let topic = selection.topic {
            VStack(alignment: .leading, spacing: Space.m) {
                HStack(alignment: .firstTextBaseline) {
                    Text(topic.title).font(.role(.emphasis, weight: .semibold))
                    Spacer()
                    if let last = combined(topic).last(where: { $0 != nil }) ?? nil {
                        Text(topic.format(last)).font(.role(.emphasis, design: .rounded).monospacedDigit()).foregroundStyle(MonitorStyle.quiet)
                    }
                }
                chips
                chart(topic).frame(height: 150)
                    .background(alignment: .bottom) { MonitorStyle.track.frame(height: 1) }
                HStack {
                    Text("\(range.label) 전").font(.role(.caption)).foregroundStyle(MonitorStyle.quiet)
                    Spacer()
                    Text("지금").font(.role(.caption)).foregroundStyle(MonitorStyle.quiet)
                }
                stats(topic)
                if !topic.legend.isEmpty {
                    HStack(spacing: Space.l) {
                        ForEach(Array(topic.legend.enumerated()), id: \.offset) { index, name in
                            HStack(spacing: Space.xs) {
                                Capsule().fill(index == 0 ? MonitorStyle.primary : MonitorStyle.secondary).frame(width: 12, height: 3)
                                Text(name).font(.role(.detail)).foregroundStyle(MonitorStyle.quiet)
                            }
                        }
                    }
                }
            }
            .padding(Space.l)
            .frame(width: MonitorStyle.width + 40)
            .foregroundStyle(Ink.primary)
            .task(id: "\(topic.rawValue)-\(rangeValue)") {
                while !Task.isCancelled {
                    series = await monitor.history(topic.metrics, range: range, count: Self.buckets)
                    try? await Task.sleep(for: .seconds(range.usesRecentReadings ? 2 : 30))
                }
            }
        }
    }

    private var range: HistoryRange { HistoryRange(rawValue: rangeValue) ?? .oneHour }

    private var chips: some View {
        HStack(spacing: Space.xs) {
            ForEach(Self.ranges) { item in
                let chosen = item.rawValue == rangeValue
                Button { rangeValue = item.rawValue } label: {
                    Text(item.label).font(.role(.detail, weight: chosen ? .semibold : .regular))
                        .foregroundStyle(chosen ? Ink.onAccent : Ink.secondary)
                        .padding(.horizontal, Space.s)
                        .frame(height: 24)
                        .background(chosen ? AnyShapeStyle(MonitorStyle.gradient) : AnyShapeStyle(Fill.card), in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder private func chart(_ topic: HistoryTopic) -> some View {
        if topic.metrics.count > 1, !topic.sums {
            DualSparkline(down: series[topic.metrics[0]] ?? [], up: series[topic.metrics[1]] ?? [])
        } else {
            Sparkline(values: combined(topic), ceiling: topic.ceiling)
        }
    }

    /// The topic's curve: the single metric, or the parts added together.
    private func combined(_ topic: HistoryTopic) -> [Double?] {
        let lists = topic.metrics.map { series[$0] ?? [] }
        guard topic.sums, lists.count > 1 else { return lists.first ?? [] }
        let count = lists.map(\.count).max() ?? 0
        return (0..<count).map { index in
            let values = lists.compactMap { index < $0.count ? $0[index] : nil }
            return values.isEmpty ? nil : values.reduce(0, +)
        }
    }

    private func stats(_ topic: HistoryTopic) -> some View {
        let values = combined(topic).compactMap { $0 }.filter(\.isFinite)
        return HStack(spacing: 0) {
            stat("낮음", values.min().map(topic.format) ?? "-")
            stat("평균", values.isEmpty ? "-" : topic.format(values.reduce(0, +) / Double(values.count)))
            stat("높음", values.max().map(topic.format) ?? "-")
        }
        .padding(.vertical, Space.m)
        .background(Fill.card, in: RoundedRectangle(cornerRadius: Radius.m, style: .continuous))
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(spacing: Space.xs) {
            Text(value).font(.role(.emphasis, design: .rounded).monospacedDigit())
            Text(label).font(.role(.caption)).foregroundStyle(MonitorStyle.quiet)
        }
        .frame(maxWidth: .infinity)
    }
}
