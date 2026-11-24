import AppKit
import SwiftUI

// The parts every screen is built from. A screen arranges these; it does not draw its own
// cards, buttons, tiles or headers. Settings rows are in SettingsParts.swift.

/// Grouped content on glass: the soft card behind settings groups, lists and tables.
struct Card<Content: View>: View {
    var padding: CGFloat = 0
    @ViewBuilder var content: Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.m, style: .continuous)
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Fill.card, in: shape)
            .overlay(shape.strokeBorder(Line.subtle, lineWidth: 1))
    }
}

/// A raised block in a floating panel (the monitor's dashboard and details). `lit` is the
/// launcher's selected-row light: the block whose details are showing.
struct Panel<Content: View>: View {
    var lit = false
    var padding: CGFloat = Space.l
    @ViewBuilder var content: Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.l, style: .continuous)
        VStack(alignment: .leading, spacing: Space.m) { content }
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(lit ? Fill.selected : Fill.card, in: shape)
            .overlay(shape.strokeBorder(lit ? Tint.light(Brand.glow) : Line.subtle, lineWidth: 1))
            .shadow(color: lit ? Tint.edge(Brand.glow) : .clear, radius: Space.m)
            .animation(.easeOut(duration: 0.15), value: lit)
    }
}

/// The quiet head of a panel or block: a symbol and a word, and an optional value at the end.
struct PanelHeader: View {
    let title: String
    var symbol: String?
    var trailing: String?

    var body: some View {
        HStack(spacing: Space.s) {
            if let symbol { Image(systemName: symbol).font(.role(.caption, weight: .semibold)) }
            Text(title).font(.role(.detail, weight: .medium))
            Spacer(minLength: Space.s)
            if let trailing { Text(trailing).font(.role(.detail).monospacedDigit()) }
        }
        .foregroundStyle(Ink.tertiary)
    }
}

/// One large number with its unit, and a line under it.
struct Figure: View {
    let value: String
    var unit = ""
    var caption: String?
    var size: TextRole = .figure

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            HStack(alignment: .firstTextBaseline, spacing: Space.xs) {
                Text(value).font(.role(size, design: .rounded)).monospacedDigit()
                if !unit.isEmpty { Text(unit).font(.role(.emphasis, design: .rounded)).foregroundStyle(Ink.tertiary) }
            }
            if let caption { Text(caption).font(.role(.detail)).foregroundStyle(Ink.tertiary).lineLimit(1) }
        }
    }
}

/// A label and its value on one line, as in a ledger. `dot` marks the series it belongs to.
struct TableRow: View {
    let label: String
    let value: String
    var dot: Color?

    var body: some View {
        HStack(spacing: Space.s) {
            if let dot { Capsule().fill(dot).frame(width: 3, height: 12) }
            Text(label).font(.role(.body)).foregroundStyle(Ink.secondary).lineLimit(1)
            Spacer(minLength: Space.s)
            Text(value).font(.role(.body, design: .rounded).monospacedDigit()).lineLimit(1)
        }
    }
}

/// A white SF Symbol on a colored rounded square: sidebar items, features, permissions.
struct IconTile: View {
    let symbol: String
    let color: Color
    var size: CGFloat = IconSize.tile

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.55, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(LinearGradient(colors: [color.opacity(0.95), color.opacity(0.75)], startPoint: .top, endPoint: .bottom),
                        in: RoundedRectangle(cornerRadius: size * 0.26, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// The app's own icon, as the system knows it.
struct AppIconImage: View {
    var size: CGFloat = 64
    var body: some View {
        Image(nsImage: NSApp.applicationIconImage ?? NSImage()).resizable().interpolation(.high).frame(width: size, height: size)
    }
}

/// One key drawn as a small cap ("⌥", "V", "1").
struct KeyCap: View {
    let label: String
    var highlighted = false

    var body: some View {
        Text(label)
            .font(.role(.detail, weight: .semibold, design: .monospaced))
            .foregroundStyle(highlighted ? Ink.onAccent : Ink.secondary)
            .frame(minWidth: Theme.keyCapSize, minHeight: Theme.keyCapSize)
            .padding(.horizontal, label.count > 1 ? Space.xs : 0)
            .background(highlighted ? Color.white : Fill.control, in: RoundedRectangle(cornerRadius: Radius.xs, style: .continuous))
    }
}

/// A shortcut as key caps ("⌥", "Space").
struct KeyCaps: View {
    let parts: [String]
    var body: some View {
        HStack(spacing: Space.xs) {
            ForEach(Array(parts.enumerated()), id: \.offset) { _, part in KeyCap(label: part) }
        }
    }
}

/// A short line set apart: a warning above a page's groups, or a note.
struct Notice: View {
    enum Tone { case warning, info }
    let text: String
    var tone: Tone = .warning
    var action: (title: String, run: () -> Void)?

    private var color: Color { tone == .warning ? Brand.peach : Brand.glow }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.m, style: .continuous)
        HStack(alignment: .top, spacing: Space.m) {
            Image(systemName: tone == .warning ? "exclamationmark.triangle.fill" : "info.circle.fill").foregroundStyle(color)
            Text(text).font(.role(.secondary)).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: Space.s)
            if let action { RowButton(action.title, action: action.run) }
        }
        .padding(Space.m)
        .background(Tint.wash(color), in: shape)
        .overlay(shape.strokeBorder(Tint.edge(color), lineWidth: 1))
    }
}

/// What a list shows when it has nothing: a symbol, a line, an explanation and maybe a way to start.
struct EmptyState: View {
    let symbol: String
    let title: String
    var detail: String?
    var action: (title: String, run: () -> Void)?

    var body: some View {
        VStack(spacing: Space.s) {
            Image(systemName: symbol).font(.role(.title)).foregroundStyle(Ink.disabled)
            Text(title).font(.role(.body, weight: .medium))
            if let detail {
                Text(detail).font(.role(.detail)).foregroundStyle(Ink.tertiary).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            }
            if let action { RowButton(action.title, action: action.run).padding(.top, Space.xs) }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Space.xxl)
        .padding(.horizontal, Space.l)
    }
}

/// A small word in a capsule ("필요", "선택", "항상 켜짐").
struct Badge: View {
    let text: String
    var color: Color = .white

    var body: some View {
        Text(text)
            .font(.role(.caption, weight: .semibold))
            .foregroundStyle(color == .white ? Ink.tertiary : color)
            .padding(.horizontal, Space.s)
            .frame(height: 16)
            .background(Tint.wash(color), in: Capsule())
    }
}

/// The button of a row, a card or a notice: always the small system button.
struct RowButton: View {
    let title: String
    var role: ButtonRole?
    let action: () -> Void

    init(_ title: String, role: ButtonRole? = nil, action: @escaping () -> Void) {
        self.title = title
        self.role = role
        self.action = action
    }

    var body: some View {
        Button(title, role: role, action: action).controlSize(.small)
    }
}

/// A small labelled button of a panel's footer ("입력창", "종료").
struct FooterButton: View {
    let title: String
    let symbol: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.role(.detail))
                .foregroundStyle(Ink.secondary)
                .padding(.horizontal, Space.s)
                .frame(height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(title)
    }
}

/// A square symbol button: a panel's pin and settings, and the switcher between its screens.
/// `selected` lights it with the accent.
struct IconButton: View {
    let symbol: String
    let label: String
    var selected = false
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.role(.body, weight: .medium))
                .foregroundStyle(selected ? Brand.accent : Ink.secondary)
                .frame(width: 28, height: 28)
                .background(selected ? Fill.selected : hovered ? Fill.control : Color.clear, in: RoundedRectangle(cornerRadius: Radius.s, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .help(label)
        .accessibilityLabel(label)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Work under way, at row size.
struct Spinner: View {
    var body: some View { ProgressView().controlSize(.small) }
}

/// The switch of a row or a header. Drawn by the app (`TrackSwitch`): the system switch turns grey
/// whenever the app is not the active one, so on and off could not be told apart.
struct RowSwitch: View {
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        TrackSwitch(isOn: $isOn).accessibilityLabel(title)
    }
}

/// A switch with its label on the left, inside a panel or a card's own content (not a settings row).
struct LabeledSwitch: View {
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: Space.s) {
            Text(title).font(.role(.secondary))
            Spacer(minLength: Space.s)
            RowSwitch(title: title, isOn: $isOn)
        }
    }
}

/// Two to four choices side by side (자동 / 직접, 얇게 / 보통 / 굵게).
struct Segmented<Value: Hashable>: View {
    let title: String
    @Binding var selection: Value
    let options: [Value]
    let label: (Value) -> String

    var body: some View {
        Picker(title, selection: $selection) {
            ForEach(options, id: \.self) { Text(label($0)).tag($0) }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .controlSize(.small)
    }
}

/// A pop-up menu of choices in a row.
struct RowMenu<Value: Hashable>: View {
    let title: String
    @Binding var selection: Value
    let options: [Value]
    let label: (Value) -> String

    var body: some View {
        Picker(title, selection: $selection) {
            ForEach(options, id: \.self) { Text(label($0)).tag($0) }
        }
        .labelsHidden()
        .fixedSize()
        .controlSize(.small)
    }
}

/// One macOS permission: what it is for, whether it is granted, and the way to grant it.
struct PermissionCard: View {
    let permission: Permission
    let granted: Bool

    var body: some View {
        HStack(spacing: Space.m) {
            IconTile(symbol: permission.symbol, color: permission.color, size: IconSize.tileLarge)
            VStack(alignment: .leading, spacing: Space.xs) {
                HStack(spacing: Space.s) {
                    Text(permission.title).font(.role(.body, weight: .medium))
                    Badge(text: permission.required ? "필요" : "선택", color: permission.required ? Brand.peach : .white)
                }
                Text(permission.purpose).font(.role(.detail)).foregroundStyle(Ink.tertiary).fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if granted {
                Label("허락됨", systemImage: "checkmark.circle.fill").font(.role(.secondary, weight: .medium)).foregroundStyle(Status.success)
            } else if let grant = permission.grant {
                RowButton("허락하기", action: grant)
            } else if let instructions = permission.instructions {
                Text(instructions).font(.role(.detail)).foregroundStyle(Status.warning).multilineTextAlignment(.trailing).frame(maxWidth: 170, alignment: .trailing)
            }
        }
        .padding(.horizontal, Space.l)
        .padding(.vertical, Space.m)
    }
}

/// One choice in a pop-up menu: its icon, and the menu's own check mark when it is the current one.
/// A toggle underneath, since a menu draws its check mark only for one.
struct MenuChoice: View {
    let title: String
    var symbol: String?
    let checked: Bool
    let action: () -> Void

    var body: some View {
        Toggle(isOn: Binding(get: { checked }, set: { _ in action() })) {
            if let symbol { Label(title, systemImage: symbol) } else { Text(title) }
        }
    }
}
