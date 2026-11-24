import SwiftUI
import ToolsmithKit

/// The charge limit, whoever enforces it: what the battery is doing now (charging, held, discharging
/// or topping up), the level against the limit, the limits to pick from, and the two one-offs
/// (discharge to the limit, charge to 100% once). Shown in the settings, the menu bar panel and the
/// monitor's battery details.
struct ChargeControls: View {
    @ObservedObject var charge: ChargeController
    var tint: Color = Brand.lavender
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? Space.s : Space.m) {
            if let snapshot = charge.snapshot {
                ChargeStateView(snapshot: snapshot, tint: tint, compact: compact,
                                choices: charge.choices, error: charge.error,
                                onLimit: { charge.setLimit($0 >= 100 ? nil : $0) },
                                onDischarge: { charge.setDischarging($0) },
                                onTopUp: { charge.setToppingUp($0) })
            }
        }
        .task {
            // macOS's limit can also change in System Settings, and a top-up ends by itself.
            while !Task.isCancelled {
                charge.refresh()
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }
}

/// The charge state drawn from a snapshot alone, so a development build can draw any state.
struct ChargeStateView: View {
    let snapshot: ChargeSnapshot
    var tint: Color = Brand.lavender
    var compact = false
    let choices: [Int]
    var error: String?
    let onLimit: (Int) -> Void
    let onDischarge: (Bool) -> Void
    let onTopUp: (Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? Space.s : Space.m) {
            header
            ChargeGauge(level: snapshot.level, limit: snapshot.activity == .toppingUp ? nil : snapshot.limit, tint: color)
            if snapshot.abilities.canHold || snapshot.abilities.canDischarge {
                VStack(alignment: .leading, spacing: Space.xs) {
                    Text("Limit").font(.role(.detail)).foregroundStyle(Ink.tertiary)
                    LimitPicker(choices: choices, selected: snapshot.limit ?? 100, tint: tint, onPick: onLimit)
                }
            }
            actions
            Text(ChargeSummary.explanation(snapshot)).font(.role(.detail)).foregroundStyle(Ink.tertiary)
                .fixedSize(horizontal: false, vertical: true)
            if let error {
                Text(error).font(.role(.detail)).foregroundStyle(Status.warning).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: Space.m) {
            IconTile(symbol: Self.symbol(snapshot.activity), color: color, size: compact ? IconSize.tile : IconSize.tileLarge)
            VStack(alignment: .leading, spacing: Space.xs) {
                Text(ChargeSummary.headline(snapshot)).font(.role(compact ? .body : .emphasis, weight: .semibold)).lineLimit(1)
                Text(subline).font(.role(.detail)).foregroundStyle(Ink.tertiary).lineLimit(1)
            }
            Spacer(minLength: Space.s)
            if let percent = snapshot.percent {
                VStack(alignment: .trailing, spacing: Space.xs) {
                    Text(verbatim: "\(percent)%").font(.role(compact ? .heading : .title, weight: .semibold, design: .rounded)).monospacedDigit()
                    if let watts = flowText {
                        Text(watts).font(.role(.caption, design: .rounded)).foregroundStyle(Ink.tertiary).monospacedDigit()
                    }
                }
            }
        }
    }

    /// The limit and the adapter, in one sentence per case so each language orders its words.
    private var subline: String {
        switch (snapshot.limit, snapshot.onAdapter) {
        case (let limit?, true): return String(localized: "Limit \(limit)% · Adapter connected")
        case (let limit?, false): return String(localized: "Limit \(limit)% · Adapter not connected")
        case (nil, true): return String(localized: "No limit · Adapter connected")
        case (nil, false): return String(localized: "No limit · Adapter not connected")
        }
    }

    /// Watts in or out of the battery: what tells holding (about 0) from charging and discharging.
    private var flowText: String? {
        guard let watts = snapshot.batteryWatts, watts.isFinite else { return nil }
        let size = MonitorText.watts(abs(watts))
        if watts > 0.3 { return String(localized: "Battery +\(size)") }
        if watts < -0.3 { return String(localized: "Battery −\(size)") }
        return String(localized: "Battery idle")
    }

    @ViewBuilder private var actions: some View {
        let discharging = snapshot.activity == .discharging
        let toppingUp = snapshot.activity == .toppingUp
        let showDischarge = discharging || snapshot.canDischarge
        let showTopUp = toppingUp || snapshot.canTopUp
        if showDischarge || showTopUp {
            HStack(spacing: Space.s) {
                if showDischarge, let limit = snapshot.limit {
                    ActionChip(title: discharging ? String(localized: "Stop Discharging") : String(localized: "Discharge to \(limit)%"),
                               symbol: "arrow.down.to.line", on: discharging, tint: Status.warning) { onDischarge(!discharging) }
                }
                if showTopUp {
                    ActionChip(title: toppingUp ? String(localized: "Back to the Limit") : String(localized: "Charge to 100% Once"),
                               symbol: "bolt.fill", on: toppingUp, tint: Status.success) { onTopUp(!toppingUp) }
                }
            }
        }
    }

    private var color: Color {
        switch snapshot.activity {
        case .charging, .toppingUp: return Status.success
        case .holding: return tint
        case .discharging: return Status.warning
        case .onBattery: return Tile.gray
        }
    }

    static func symbol(_ activity: ChargeActivity) -> String {
        switch activity {
        case .charging: return "battery.100.bolt"
        case .holding: return "powerplug.fill"
        case .discharging: return "arrow.down.to.line"
        case .toppingUp: return "bolt.fill"
        case .onBattery: return "battery.75"
        }
    }
}

/// The battery as a bar, with the limit marked and the part above it set apart.
struct ChargeGauge: View {
    let level: Double?
    let limit: Int?
    let tint: Color

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let shape = RoundedRectangle(cornerRadius: Radius.xs, style: .continuous)
            ZStack(alignment: .leading) {
                shape.fill(Fill.control)
                if let limit {
                    // Above the limit: the room the battery is kept out of.
                    Rectangle().fill(Fill.control)
                        .frame(width: width * CGFloat(100 - limit) / 100)
                        .offset(x: width * CGFloat(limit) / 100)
                }
                if let level {
                    shape.fill(LinearGradient(colors: [Tint.strong(tint), tint], startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(4, width * CGFloat(min(max(level, 0), 100)) / 100))
                }
                if let limit {
                    Capsule().fill(Ink.secondary)
                        .frame(width: 2, height: proxy.size.height + 6)
                        .offset(x: width * CGFloat(limit) / 100 - 1)
                }
            }
            .clipShape(Rectangle().inset(by: -4))
        }
        .frame(height: 10)
        .padding(.vertical, Space.xs)
    }
}

/// The limits as a row of choices; 100 reads as "None".
struct LimitPicker: View {
    let choices: [Int]
    let selected: Int?
    let tint: Color
    let onPick: (Int) -> Void

    var body: some View {
        HStack(spacing: Space.xs) {
            ForEach(choices, id: \.self) { value in
                let on = value == selected
                Button { onPick(value) } label: {
                    Text(value >= 100 ? String(localized: "None") : "\(value)%")
                        .font(.role(.detail, weight: on ? .semibold : .regular).monospacedDigit())
                        .frame(maxWidth: .infinity, minHeight: 22)
                        .foregroundStyle(on ? Ink.onAccent : Ink.secondary)
                        .background(on ? AnyShapeStyle(tint) : AnyShapeStyle(Fill.control),
                                    in: RoundedRectangle(cornerRadius: Radius.xs, style: .continuous))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}
