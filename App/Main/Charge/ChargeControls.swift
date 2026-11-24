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
                LabeledSwitch(title: "지금 충전 보류", isOn: Binding(get: { charge.paused }, set: { charge.setPaused($0) }))
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
            Text(charge.toppingUp ? "이번만 100%까지 충전하는 중" : "외출 전이라면 이번만 끝까지")
                .font(.role(.detail)).foregroundStyle(Ink.tertiary).lineLimit(1).minimumScaleFactor(0.85)
            Spacer(minLength: Space.xs)
            RowButton(charge.toppingUp ? "다시 제한" : "100%까지 충전") { charge.toppingUp ? charge.resumeLimit() : charge.topUp() }
        }
    }

    private var headline: String {
        if charge.toppingUp { return "충전 제한 잠시 꺼짐" }
        return charge.limit.map { "\($0)%까지만 충전" } ?? "충전 제한 없음"
    }

    /// What the battery is doing now, in the limit's terms.
    private var activity: String {
        guard let battery else { return "" }
        let level = "\(Int(battery.level.rounded()))%"
        if battery.isCharging { return "\(level) · 충전 중" }
        if battery.onAdapter {
            if charge.paused { return "\(level) · 충전 보류 중" }
            guard let limit = charge.limit else { return "\(level) · 어댑터 연결됨" }
            if battery.level > Double(limit) + 1 { return "\(level) · \(limit)%까지 내리는 중" }
            // Well under the limit and still not charging: something else (a weak adapter) holds it.
            return battery.level < Double(limit) - ChargeLimit.adapterHysteresis - 1 ? "\(level) · 어댑터 연결됨, 충전 안 함" : "\(level) · 제한에서 멈춤"
        }
        return "\(level) · 배터리 사용 중"
    }

    private var dischargeTitle: String {
        charge.limit.map { "어댑터를 꽂은 채 \($0)%까지 배터리로 쓰기" } ?? "어댑터를 꽂은 채 배터리로 쓰기"
    }

    private var note: String {
        if charge.state == .system {
            return "macOS 의 충전 제한을 그대로 씁니다. 시스템 설정 → 배터리 의 값과 같고, 맥이 잠자는 동안에도 지켜집니다. 제한보다 많이 차 있으면 어댑터를 꽂은 채 제한까지 천천히 내려갑니다. macOS 는 80% 아래를 허용하지 않습니다."
        }
        let band = Int(charge.status.map { $0.canPause ? ChargeLimit.hysteresis : ChargeLimit.adapterHysteresis } ?? ChargeLimit.hysteresis)
        if charge.canPause {
            return "배터리가 이만큼 차면 충전을 멈추고, \(band)%p 아래로 내려가면 다시 충전합니다."
        }
        return "이 맥은 충전만 멈추는 방법이 없어, 이만큼 차면 어댑터를 잠시 끊고 배터리로 쓰다가 \(band)%p 아래로 내려가면 다시 충전합니다. 잠자기 전에는 어댑터를 다시 잇습니다."
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

/// The limits as a row of choices; 100 reads as "없음".
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
                    Text(value >= 100 ? "없음" : "\(value)%")
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
