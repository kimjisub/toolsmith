import SwiftUI
import ToolsmithKit

/// The charge limit, whoever enforces it: where the battery stands against the limit, the limits to
/// pick from, charging to full this once, and (helper only) pausing and discharging. Shown in the
/// settings and in the monitor's battery details.
struct ChargeControls: View {
    @ObservedObject var charge: ChargeController
    /// The battery now, for the gauge and the one-line state.
    let battery: BatteryInfo?
    var tint: Color = Brand.lavender
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 10 : 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(headline).font(.role(compact ? .secondary : .body, weight: .medium))
                Spacer(minLength: Space.s)
                Text(activity).font(.role(.detail)).foregroundStyle(Ink.tertiary).lineLimit(1)
            }
            ChargeGauge(level: battery?.level, limit: charge.toppingUp ? nil : charge.limit, tint: tint)
            LimitPicker(choices: charge.choices, selected: charge.toppingUp ? nil : (charge.limit ?? 100), tint: tint) { charge.setLimit($0 >= 100 ? nil : $0) }
            if charge.canTopUp, charge.limit != nil || charge.toppingUp {
                topUpRow
            }
            if charge.canPause {
                LabeledSwitch(title: String(localized: "Pause Charging Now"), isOn: Binding(get: { charge.paused }, set: { charge.setPaused($0) }))
            }
            if charge.canDischarge {
                LabeledSwitch(title: dischargeTitle, isOn: Binding(get: { charge.discharging }, set: { charge.setDischarging($0) }))
            }
            if !compact {
                Text(note).font(.role(.detail)).foregroundStyle(Ink.tertiary).fixedSize(horizontal: false, vertical: true)
            }
            if let error = charge.error {
                Text(error).font(.role(.detail)).foregroundStyle(Status.warning).fixedSize(horizontal: false, vertical: true)
            }
        }
        .font(.role(.secondary))
        .task {
            // macOS's limit can also change in System Settings, and a top-up ends by itself.
            while !Task.isCancelled {
                charge.refresh()
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }

    private var topUpRow: some View {
        HStack(spacing: Space.s) {
            Image(systemName: charge.toppingUp ? "bolt.fill" : "bolt").foregroundStyle(tint).frame(width: 14)
            Text(charge.toppingUp ? String(localized: "Charging to 100% this once") : String(localized: "Going out? Charge to full this once"))
                .font(.role(.detail)).foregroundStyle(Ink.tertiary).lineLimit(1).minimumScaleFactor(0.85)
            Spacer(minLength: Space.xs)
            RowButton(charge.toppingUp ? String(localized: "Limit Again") : String(localized: "Charge to 100%")) { charge.toppingUp ? charge.resumeLimit() : charge.topUp() }
        }
    }

    private var headline: String {
        if charge.toppingUp { return String(localized: "Charge limit paused") }
        return charge.limit.map { String(localized: "Charging up to \($0)%") } ?? String(localized: "No charge limit")
    }

    /// What the battery is doing now, in the limit's terms.
    private var activity: String {
        guard let battery else { return "" }
        let level = "\(Int(battery.level.rounded()))%"
        return "\(level) · \(state(battery))"
    }

    private func state(_ battery: BatteryInfo) -> String {
        if battery.isCharging { return String(localized: "Charging") }
        if battery.onAdapter {
            if charge.paused { return String(localized: "Charging paused") }
            guard let limit = charge.limit else { return String(localized: "Adapter connected") }
            if battery.level > Double(limit) + 1 { return String(localized: "Lowering to \(limit)%") }
            // Well under the limit and still not charging: something else (a weak adapter) holds it.
            return battery.level < Double(limit) - ChargeLimit.adapterHysteresis - 1 ? String(localized: "Adapter connected, not charging") : String(localized: "Held at the limit")
        }
        return String(localized: "On battery")
    }

    private var dischargeTitle: String {
        charge.limit.map { String(localized: "Use the battery down to \($0)% while plugged in") } ?? String(localized: "Use the battery while plugged in")
    }

    private var note: String {
        if charge.state == .system {
            return String(localized: "Uses macOS’s own charge limit. It is the same value as System Settings → Battery and is kept while the Mac sleeps. If the battery is fuller than the limit, it slowly runs down to the limit while plugged in. macOS does not allow limits below 80%.")
        }
        let band = Int(charge.status.map { $0.canPause ? ChargeLimit.hysteresis : ChargeLimit.adapterHysteresis } ?? ChargeLimit.hysteresis)
        if charge.canPause {
            return String(localized: "Charging stops when the battery reaches this level and starts again when it drops \(band) percentage points below.")
        }
        return String(localized: "This Mac cannot pause charging by itself, so at this level the adapter is disconnected for a while and the Mac runs on battery until it drops \(band) percentage points below, then charges again. The adapter is reconnected before the Mac sleeps.")
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
