import SwiftUI
import ToolsmithKit

/// The charge limit inside the battery details.
private struct ChargeLimitPanel: View {
    @ObservedObject var charge: ChargeController
    let battery: BatteryInfo
    let onChargeSettings: () -> Void

    var body: some View {
        Panel {
            PanelHeader(title: String(localized: "Charge Limit"), symbol: "battery.75percent")
            if charge.canControl {
                ChargeControls(charge: charge, tint: MonitorStyle.tertiary, compact: true)
            } else {
                HStack(spacing: Space.s) {
                    Text("Turn it on in Settings → Battery Charging").font(.role(.secondary)).foregroundStyle(MonitorStyle.quiet)
                    Spacer()
                    RowButton(String(localized: "Open"), action: onChargeSettings)
                }
            }
        }
    }
}

struct BatteryDetailView: View {
    @ObservedObject var monitor: MonitorModel
    @ObservedObject var processes: ProcessMonitor
    /// nil while the battery charging feature is switched off.
    let charge: ChargeController?
    @ObservedObject var selection: HistorySelection
    let onChargeSettings: () -> Void
    private var s: SystemSnapshot { monitor.snapshot }

    var body: some View {
        VStack(spacing: Space.s) {
            if let battery = s.battery {
                HistoryBlock(topic: .batteryLevel, selection: selection) {
                    PanelHeader(title: String(localized: "Battery"), symbol: battery.isCharging ? "battery.100.bolt" : "battery.75")
                    Figure(value: MonitorText.whole(battery.level), unit: "%", caption: battery.stateText)
                    MeterBar(fraction: battery.level / 100, fill: AnyShapeStyle(battery.level < 20 ? MonitorStyle.hot : MonitorStyle.tertiary), height: 6)
                }
                if let charge {
                    ChargeLimitPanel(charge: charge, battery: battery, onChargeSettings: onChargeSettings)
                }
                HistoryBlock(topic: .power, selection: selection) {
                    PanelHeader(title: String(localized: "Power Flow"), symbol: "bolt")
                    PowerFlow(power: s.power)
                }
                Panel {
                    PanelHeader(title: String(localized: "Health"), symbol: "heart")
                    if let health = battery.health {
                        Figure(value: MonitorText.whole(health), unit: "%", caption: String(localized: "Current capacity compared with when new"))
                    }
                    if let design = battery.designCapacity { TableRow(label: String(localized: "Design Capacity"), value: "\(design) mAh") }
                    if let maximum = battery.maximumCapacity { TableRow(label: String(localized: "Maximum Capacity"), value: "\(maximum) mAh") }
                    if let cycles = battery.cycleCount { TableRow(label: String(localized: "Cycle Count"), value: String(localized: "\(cycles) cycles")) }
                    if let condition = battery.conditionText { TableRow(label: String(localized: "Condition"), value: condition) }
                }
                HistoryBlock(topic: .batteryTemperature, selection: selection) {
                    PanelHeader(title: String(localized: "Temperature"), symbol: "thermometer.medium")
                    if let temperature = battery.temperature { HeatRow(label: String(localized: "Battery"), celsius: temperature) }
                    if let mode = monitor.energyMode { TableRow(label: String(localized: "Energy Mode"), value: mode.label) }
                    if let watts = battery.adapterWatts, battery.onAdapter { TableRow(label: String(localized: "Adapter"), value: "\(watts) W") }
                }
            }
            if !monitor.accessories.isEmpty {
                Panel {
                    PanelHeader(title: String(localized: "Connected Devices"), symbol: "keyboard")
                    ForEach(monitor.accessories) { accessory in
                        HStack(spacing: Space.s) {
                            Text(accessory.name).font(MonitorStyle.body).foregroundStyle(Ink.secondary).lineLimit(1)
                            Spacer()
                            MeterBar(fraction: accessory.level / 100, fill: AnyShapeStyle(MonitorStyle.tertiary), height: 4).frame(width: 54)
                            Text(MonitorText.percent(accessory.level)).font(MonitorStyle.number).frame(width: 40, alignment: .trailing)
                        }
                    }
                }
            }
            UsageList(title: String(localized: "Apps Using the Most Energy"), symbol: "leaf", entries: processes.energy, format: { String(format: "%.1f", $0) }, trailing: String(localized: "Energy Impact"))
        }
    }
}

/// Where the power goes, as a flow: the sources (adapter, battery) feed the Mac, which splits into
/// its parts. Every ribbon is drawn on one scale, so its thickness is its watts on both sides.
struct PowerFlow: View {
    let power: PowerBreakdown

    struct Node: Identifiable {
        let label: String
        let symbol: String
        let watts: Double
        let color: Color
        var id: String { label }
    }

    private var parts: [Node] {
        var list: [Node] = []
        func add(_ label: String, _ symbol: String, _ watts: Double?, _ color: Color) {
            if let watts, watts.isFinite, watts >= 0.05 { list.append(Node(label: label, symbol: symbol, watts: watts, color: color)) }
        }
        add("CPU", "cpu", power.cpu, MonitorStyle.primary)
        add(String(localized: "Graphics"), "square.stack.3d.up", power.gpu, MonitorStyle.secondary)
        add(String(localized: "Memory"), "memorychip", power.memory, MonitorStyle.tertiary)
        add(String(localized: "Neural Engine"), "brain", power.neuralEngine, Brand.mint)
        add(power.cpu == nil ? String(localized: "CPU & Other") : String(localized: "Other"), "ellipsis", power.other, Ink.tertiary)
        if charging == nil, let battery = power.battery, battery > 0.05 { add(String(localized: "Charge"), "battery.100.bolt", battery, MonitorStyle.tertiary) }
        return list
    }

    /// Watts going into the battery, when the adapter they branch off is known. The flow then
    /// splits before the Mac: one ribbon to the battery, one to the Mac.
    private var charging: Double? {
        guard let battery = power.battery, battery > 0.05, let adapter = power.adapter, adapter > 0.5 else { return nil }
        return min(battery, adapter)
    }

    /// What feeds the Mac: the adapter, the battery while it discharges, or both when the adapter
    /// cannot keep up.
    private var sources: [Node] {
        var list: [Node] = []
        if let adapter = power.adapter, adapter > 0.5 { list.append(Node(label: String(localized: "Adapter"), symbol: "powerplug.fill", watts: adapter, color: MonitorStyle.secondary)) }
        if let battery = power.battery, battery < -0.05 { list.append(Node(label: String(localized: "Battery"), symbol: "battery.75", watts: -battery, color: MonitorStyle.tertiary)) }
        return list
    }

    var body: some View {
        let parts = self.parts, sources = self.sources, charging = self.charging
        let total = power.system ?? parts.map(\.watts).reduce(0, +)
        let rowsHeight = CGFloat(parts.count) * (PowerFlowLayout.row + 8) + CGFloat(max(parts.count - 1, 0)) * PowerFlowLayout.rowGap
        let height = max(charging == nil ? 150 : 190, rowsHeight)
        GeometryReader { proxy in
            let layout = PowerFlowLayout(size: proxy.size, sources: sources.map(\.watts), charging: charging, parts: parts.map(\.watts))
            ZStack(alignment: .topLeading) {
                Canvas { context, _ in
                    for link in layout.links {
                        let color = link.toBattery ? MonitorStyle.tertiary : sources[link.source].color
                        context.fill(Self.ribbon(from: link.from, to: link.to),
                                     with: .linearGradient(Gradient(colors: [Tint.light(sources[link.source].color), Tint.edge(color)]),
                                                           startPoint: CGPoint(x: link.from.minX, y: 0), endPoint: CGPoint(x: link.to.minX, y: 0)))
                    }
                    for (index, part) in parts.enumerated() {
                        let from = layout.macOutlets[index], row = layout.rows[index]
                        // A ribbon thicker than its row narrows to fit as it lands.
                        let landing = min(from.height, row.height - 8)
                        let into = CGRect(x: row.minX, y: row.midY - landing / 2, width: 0, height: landing)
                        context.fill(Self.ribbon(from: from, to: into),
                                     with: .linearGradient(Gradient(colors: [Line.base, Tint.light(part.color)]),
                                                           startPoint: CGPoint(x: from.minX, y: 0), endPoint: CGPoint(x: into.minX, y: 0)))
                    }
                }
                ForEach(Array(sources.enumerated()), id: \.element.id) { index, source in
                    place(tile(symbol: source.symbol, tint: source.color, value: MonitorText.watts(source.watts), caption: source.label), in: layout.sourceTiles[index])
                }
                if let charging, let battery = layout.battery {
                    place(tile(symbol: "battery.100.bolt", tint: MonitorStyle.tertiary, value: MonitorText.watts(charging), caption: String(localized: "Charge")), in: battery)
                }
                place(tile(symbol: "laptopcomputer", tint: .white, value: MonitorText.watts(total), caption: String(localized: "Whole Mac")), in: layout.mac)
                ForEach(Array(parts.enumerated()), id: \.element.id) { index, part in
                    let rect = layout.rows[index]
                    HStack(spacing: Space.xs) {
                        Image(systemName: part.symbol).font(.role(.caption, weight: .semibold)).foregroundStyle(part.color).frame(width: 14)
                        Text(part.label).font(.role(.detail)).foregroundStyle(Ink.secondary).lineLimit(1).minimumScaleFactor(0.8)
                        Spacer(minLength: Space.xs)
                        Text(MonitorText.watts(part.watts)).font(.role(.detail, weight: .medium, design: .rounded).monospacedDigit()).fixedSize()
                    }
                    .padding(.horizontal, Space.s)
                    .frame(width: rect.width, height: rect.height)
                    .background(Surface.chip, in: RoundedRectangle(cornerRadius: Radius.xs, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: Radius.xs, style: .continuous).strokeBorder(Line.subtle, lineWidth: 1))
                    .offset(x: rect.minX, y: rect.minY)
                }
            }
        }
        .frame(height: height)
    }

    private func place(_ view: some View, in rect: CGRect) -> some View {
        view.frame(width: rect.width, height: rect.height).offset(x: rect.minX, y: rect.minY)
    }

    private func tile(symbol: String, tint: Color, value: String, caption: String) -> some View {
        VStack(spacing: Space.xs) {
            Image(systemName: symbol).font(.role(.emphasis, weight: .medium)).foregroundStyle(tint)
            Text(value).font(.role(.secondary, weight: .semibold, design: .rounded).monospacedDigit()).lineLimit(1).minimumScaleFactor(0.7)
            Text(caption).font(.role(.caption)).foregroundStyle(MonitorStyle.quiet).lineLimit(1).minimumScaleFactor(0.7)
        }
        .padding(.horizontal, Space.xs)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Surface.chip, in: RoundedRectangle(cornerRadius: Radius.s, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.s, style: .continuous).strokeBorder(Line.subtle, lineWidth: 1))
    }

    /// A band that leaves `from`'s edge and lands on `to`'s edge with an S-curve, keeping its
    /// thickness at each end.
    static func ribbon(from: CGRect, to: CGRect) -> Path {
        let mid = (from.minX + to.minX) / 2
        var path = Path()
        path.move(to: CGPoint(x: from.minX, y: from.minY))
        path.addCurve(to: CGPoint(x: to.minX, y: to.minY), control1: CGPoint(x: mid, y: from.minY), control2: CGPoint(x: mid, y: to.minY))
        path.addLine(to: CGPoint(x: to.minX, y: to.maxY))
        path.addCurve(to: CGPoint(x: from.minX, y: from.maxY), control1: CGPoint(x: mid, y: to.maxY), control2: CGPoint(x: mid, y: from.maxY))
        path.closeSubpath()
        return path
    }
}

/// The flow's geometry: source tiles, then the Mac tile (with the battery tile above it while it
/// charges), then labelled rows, with one watts-to-points scale for every ribbon.
struct PowerFlowLayout {
    /// The shortest a row gets, so its label fits; rows above it grow with their watts.
    static let row: CGFloat = 24
    static let rowGap: CGFloat = 6
    static let tile: CGFloat = 48
    static let sourceGap: CGFloat = 22
    static let bandGap: CGFloat = 2
    static let rowWidth: CGFloat = 130

    /// A ribbon from a source tile to the battery tile or the Mac tile.
    struct Link {
        let source: Int
        let toBattery: Bool
        let from: CGRect
        let to: CGRect
    }

    let sourceTiles: [CGRect]
    /// The battery being charged, above the Mac; nil when nothing flows into it.
    let battery: CGRect?
    let mac: CGRect
    let links: [Link]
    /// Where each part's ribbon leaves the Mac tile, stacked and centred on its right edge.
    let macOutlets: [CGRect]
    let rows: [CGRect]

    init(size: CGSize, sources: [Double], charging: Double?, parts: [Double]) {
        let inset: CGFloat = 10
        let middleX = sources.isEmpty ? 0 : Self.tile + Self.sourceGap
        let charge = sources.isEmpty ? 0 : max(charging ?? 0, 0)
        let supplied = sources.reduce(0, +)
        let used = parts.reduce(0, +)

        let usable = size.height - inset * 2 - Self.bandGap * CGFloat(max(parts.count, sources.count, 1))
        let scale = usable / CGFloat(max(supplied, used + charge, 0.001))
        func stack(_ watts: [Double], x: CGFloat, around centre: CGFloat) -> [CGRect] {
            let heights = watts.map { max(1.5, CGFloat($0) * scale) }
            let span = heights.reduce(0, +) + Self.bandGap * CGFloat(max(heights.count - 1, 0))
            var y = centre - span / 2
            return heights.map { height in
                defer { y += height + Self.bandGap }
                return CGRect(x: x, y: y, width: 0, height: height)
            }
        }

        // The middle column: the battery takes its share of the height, the Mac the rest.
        let tileGap: CGFloat = 6
        if charge > 0 {
            let heights = Self.share([charge, max(supplied - charge, used, 0.001)], length: size.height, gap: tileGap, minimum: 54)
            battery = CGRect(x: middleX, y: 0, width: Self.tile, height: heights[0])
            mac = CGRect(x: middleX, y: heights[0] + tileGap, width: Self.tile, height: heights[1])
        } else {
            battery = nil
            mac = CGRect(x: middleX, y: 0, width: Self.tile, height: size.height)
        }

        // Source tiles share the column by their watts, each tall enough for its label.
        var top: CGFloat = 0
        sourceTiles = Self.share(sources, length: size.height, gap: tileGap, minimum: 54).map { height in
            defer { top += height + tileGap }
            return CGRect(x: 0, y: top, width: Self.tile, height: height)
        }

        // Each source's watts, split into what goes to the battery (from the first source, the
        // adapter) and what goes to the Mac. The ribbons leave the source stacked in that order.
        let toMac = sources.enumerated().map { index, watts in index == 0 ? max(watts - charge, 0) : watts }
        let macInlets = stack(toMac, x: mac.minX, around: mac.midY)
        var made: [Link] = []
        for (index, tile) in sourceTiles.enumerated() {
            let flows = index == 0 && charge > 0 ? [charge, toMac[index]] : [toMac[index]]
            let outlets = stack(flows, x: tile.maxX, around: tile.midY)
            if let battery, flows.count == 2 {
                let into = CGRect(x: battery.minX, y: battery.midY - outlets[0].height / 2, width: 0, height: outlets[0].height)
                made.append(Link(source: index, toBattery: true, from: outlets[0], to: into))
            }
            if toMac[index] > 0.05, let outlet = outlets.last {
                made.append(Link(source: index, toBattery: false, from: outlet, to: macInlets[index]))
            }
        }
        links = made
        macOutlets = stack(parts, x: mac.maxX, around: mac.midY)

        let rowX = size.width - Self.rowWidth
        var rowTop: CGFloat = 0
        rows = Self.share(parts, length: size.height, gap: Self.rowGap, minimum: Self.row).map { height in
            defer { rowTop += height + Self.rowGap }
            return CGRect(x: rowX, y: rowTop, width: Self.rowWidth, height: height)
        }
    }

    /// Splits `length` among the items by their watts, but never below `minimum`: items that would
    /// fall short get the minimum and the rest share what is left.
    static func share(_ watts: [Double], length: CGFloat, gap: CGFloat, minimum: CGFloat) -> [CGFloat] {
        let room = length - gap * CGFloat(max(watts.count - 1, 0))
        guard room > minimum * CGFloat(watts.count) else { return watts.map { _ in minimum } }
        var floored = Set<Int>()
        while true {
            let free = room - minimum * CGFloat(floored.count)
            let freeWatts = watts.indices.filter { !floored.contains($0) }.map { watts[$0] }.reduce(0, +)
            let heights = watts.indices.map { index in
                floored.contains(index) || freeWatts <= 0 ? minimum : free * CGFloat(watts[index] / freeWatts)
            }
            let short = watts.indices.filter { !floored.contains($0) && heights[$0] < minimum }
            if short.isEmpty { return heights }
            floored.formUnion(short)
        }
    }
}
