import SwiftUI

/// A horizontal slider drawn by this app. The system slider greys out whenever the app is not the
/// active one, which a floating panel over another app always is; this one keeps its colours.
struct TrackSlider: View {
    let value: Double
    let range: ClosedRange<Double>
    let fill: Color
    var enabled = true
    /// Filled from the middle (balance) rather than from the left.
    var fillsFromCentre = false
    let onChange: (Double) -> Void

    var body: some View {
        GeometryReader { proxy in
            let knob: CGFloat = 18
            let span = max(proxy.size.width - knob, 1)
            let fraction = CGFloat((min(max(value, range.lowerBound), range.upperBound) - range.lowerBound) / (range.upperBound - range.lowerBound))
            let x = knob / 2 + span * fraction
            let start = fillsFromCentre ? knob / 2 + span / 2 : knob / 2
            ZStack(alignment: .leading) {
                Capsule().fill(Fill.selected).frame(height: 4).padding(.horizontal, knob / 2)
                Capsule().fill(enabled ? fill : Line.strong).frame(width: abs(x - start), height: 4).offset(x: min(x, start))
                Circle().fill(Color.white).shadow(color: Shade.medium, radius: 1.5, y: 0.5)
                    .frame(width: knob, height: knob).offset(x: x - knob / 2)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
                guard enabled else { return }
                let position = Double(min(max((drag.location.x - knob / 2) / span, 0), 1))
                onChange(range.lowerBound + position * (range.upperBound - range.lowerBound))
            })
        }
        .frame(height: 22)
        .opacity(enabled ? 1 : 0.5)
        .accessibilityElement()
        .accessibilityValue(Text(verbatim: "\(Int(((value - range.lowerBound) / (range.upperBound - range.lowerBound) * 100).rounded()))%"))
        .accessibilityAdjustableAction { direction in
            let step = (range.upperBound - range.lowerBound) / 20
            onChange(min(max(value + (direction == .increment ? step : -step), range.lowerBound), range.upperBound))
        }
    }
}

/// An on/off switch in the app's colours, for the same reason as `TrackSlider`.
struct TrackSwitch: View {
    @Binding var isOn: Bool

    var body: some View {
        Button { isOn.toggle() } label: {
            ZStack(alignment: isOn ? .trailing : .leading) {
                Capsule().fill(isOn ? Brand.lavender : Line.base)
                Circle().fill(Color.white).padding(2.5)
            }
            .frame(width: 40, height: 22)
            .animation(.easeOut(duration: 0.12), value: isOn)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(.isToggle)
        .accessibilityValue(isOn ? Text("On") : Text("Off"))
    }
}

/// A vertical level bar: green to the top as the sound gets louder (on a 60 dB scale). An input that
/// is not being read is drawn hatched, as reading it would light the microphone indicator.
struct LevelMeter: View {
    let level: Float
    var hatched = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.xs, style: .continuous)
        ZStack(alignment: .bottom) {
            shape.fill(Fill.control)
            if hatched {
                Canvas { context, size in
                    var path = Path()
                    var y: CGFloat = -size.width
                    while y < size.height {
                        path.move(to: CGPoint(x: 0, y: y + size.width))
                        path.addLine(to: CGPoint(x: size.width, y: y))
                        y += 4
                    }
                    context.stroke(path, with: .color(Line.strong), lineWidth: 1)
                }
                .clipShape(shape)
            } else {
                GeometryReader { proxy in
                    let fraction = CGFloat(Self.fraction(level))
                    VStack { Spacer(minLength: 0); shape.fill(fraction > 0.92 ? Status.danger : Brand.lavender).frame(height: proxy.size.height * fraction) }
                }
            }
        }
        .frame(width: 6, height: 24)
        .accessibilityHidden(true)
    }

    static func fraction(_ peak: Float) -> Float {
        guard peak > 0.001 else { return 0 }
        return min(max((20 * log10(peak) + 60) / 60, 0), 1)
    }
}


/// A one-off that is on or off, as a wide button with a symbol: lit in its tint while it runs
/// (the charge screen's "discharge" and "charge to 100% once").
struct ActionChip: View {
    let title: String
    let symbol: String
    let on: Bool
    var tint: Color = Brand.accent
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Space.xs) {
                Image(systemName: symbol).font(.role(.detail, weight: .semibold))
                Text(title).font(.role(.detail, weight: .medium)).lineLimit(1).minimumScaleFactor(0.8)
            }
            .foregroundStyle(on ? tint : Ink.secondary)
            .frame(maxWidth: .infinity, minHeight: 28)
            .padding(.horizontal, Space.s)
            .background(on ? Tint.wash(tint) : Fill.control, in: RoundedRectangle(cornerRadius: Radius.s, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Radius.s, style: .continuous).strokeBorder(on ? Tint.edge(tint) : Line.subtle, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}
