import AppKit
import SwiftUI
import ToolsmithKit

// The settings window's parts, in the shape of macOS System Settings: a page, groups of rows on a
// card, and rows with the label on the left and one control on the right. Every page, the app's
// own and every module's, is assembled from these only.

/// A page of the app's own (General, Shortcuts…): its name, an optional lead, then its groups.
/// A module's page uses `ModuleSettingsScreen` instead, which puts the module header on top.
struct SettingsPage<Content: View>: View {
    let title: String
    var lead: String?
    @ViewBuilder var content: Content

    var body: some View {
        SettingsScroll {
            VStack(alignment: .leading, spacing: Space.s) {
                Text(title).font(.role(.title, weight: .semibold))
                if let lead { SettingsLead(text: lead) }
            }
            content
        }
    }
}

/// The scrolling column every settings page sits in.
struct SettingsScroll<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xxl) { content }
                .padding(.horizontal, Space.xxl)
                .padding(.top, Space.xxl)
                .padding(.bottom, Space.xxl)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.never)
    }
}

/// The explanation under a page title or a module header.
struct SettingsLead: View {
    let text: String
    var body: some View {
        Text(text).font(.role(.secondary)).foregroundStyle(Ink.tertiary).fixedSize(horizontal: false, vertical: true)
    }
}

/// A group of rows on one card, with a title above and an optional note below. Rows are
/// separated by hairlines automatically.
struct SettingsSection<Content: View>: View {
    var title: String?
    var footer: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            if let title { Text(title).font(.role(.body, weight: .semibold)).padding(.leading, Space.xs) }
            Card {
                VStack(spacing: 0) {
                    Group(subviews: content) { rows in
                        ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                            if index > 0 { Line.subtle.frame(height: 1).padding(.leading, Space.l) }
                            row
                        }
                    }
                }
            }
            if let footer {
                Text(footer).font(.role(.detail)).foregroundStyle(Ink.tertiary).padding(.horizontal, Space.xs).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// One line of a group: what it is (with a one-line explanation), and its control on the right.
struct SettingsRow<Trailing: View>: View {
    let title: String
    var detail: String?
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: Space.l) {
            VStack(alignment: .leading, spacing: Space.xs) {
                Text(title).font(.role(.body))
                if let detail {
                    Text(detail).font(.role(.detail)).foregroundStyle(Ink.tertiary).fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            trailing
        }
        .padding(.horizontal, Space.l)
        .padding(.vertical, Space.m)
        .frame(minHeight: 44)
    }
}

extension SettingsRow where Trailing == EmptyView {
    init(title: String, detail: String? = nil) {
        self.init(title: title, detail: detail) { EmptyView() }
    }
}

/// A row whose control is a switch.
struct ToggleRow: View {
    let title: String
    var detail: String?
    @Binding var isOn: Bool

    var body: some View {
        SettingsRow(title: title, detail: detail) { RowSwitch(title: title, isOn: $isOn) }
    }
}

/// A row whose control is a pop-up menu.
struct PickerRow<Value: Hashable>: View {
    let title: String
    var detail: String?
    @Binding var selection: Value
    let options: [Value]
    let label: (Value) -> String

    var body: some View {
        SettingsRow(title: title, detail: detail) {
            RowMenu(title: title, selection: $selection, options: options, label: label)
        }
    }
}

/// A row whose control is a slider, with the value written next to it.
struct SliderRow: View {
    let title: String
    var detail: String?
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double = 1
    let valueText: (Double) -> String

    var body: some View {
        SettingsRow(title: title, detail: detail) {
            TrackSlider(value: value, range: range, fill: Brand.lavender) { new in
                value = (new / step).rounded() * step
            }
            .frame(width: 180)
            .accessibilityLabel(title)
            Text(valueText(value)).font(.role(.secondary).monospacedDigit()).foregroundStyle(Ink.tertiary).frame(width: 40, alignment: .trailing)
        }
    }
}

/// A row that is a text field, with an optional button after it.
struct FieldRow: View {
    let placeholder: String
    @Binding var text: String
    var secure = false
    var monospaced = false
    var button: (title: String, enabled: Bool, run: () -> Void)?
    var onSubmit: () -> Void = {}

    var body: some View {
        HStack(spacing: Space.s) {
            Group {
                if secure { SecureField(placeholder, text: $text) } else { TextField(placeholder, text: $text) }
            }
            .textFieldStyle(.roundedBorder)
            .font(.role(.secondary, design: monospaced ? .monospaced : .default))
            .onSubmit(onSubmit)
            if let button { RowButton(button.title, action: button.run).disabled(!button.enabled) }
        }
        .padding(.horizontal, Space.l)
        .padding(.vertical, Space.m)
    }
}

/// A row of a list the user keeps (apps to ignore): an icon, a name, a small second line, and a
/// button that takes it out.
struct ListRow: View {
    var icon: NSImage?
    let title: String
    var subtitle: String?
    let removeLabel: String
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: Space.m) {
            if let icon { Image(nsImage: icon).resizable().frame(width: IconSize.app, height: IconSize.app) }
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.role(.body))
                if let subtitle { Text(subtitle).font(.role(.caption, design: .monospaced)).foregroundStyle(Ink.tertiary).lineLimit(1) }
            }
            Spacer()
            Button(action: onRemove) { Image(systemName: "minus.circle.fill") }
                .buttonStyle(.plain)
                .foregroundStyle(Ink.tertiary)
                .accessibilityLabel(removeLabel)
        }
        .padding(.horizontal, Space.l)
        .padding(.vertical, Space.s)
    }
}

/// A row of buttons that act on the whole group ("Add App…").
struct ActionsRow<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        HStack(spacing: Space.s) { content; Spacer() }
            .padding(.horizontal, Space.l)
            .padding(.vertical, Space.m)
    }
}

/// Content that is not a row (a chart, an editor) placed in a group with the rows' margins.
/// The escape hatch: use it for data a row cannot show, not for laying out controls.
struct ContentRow<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Space.l)
    }
}

/// The head of a module's page, as in System Settings: the module's tile, name and summary, and
/// its switch. Below it, what keeps a switched-on module from running.
struct ModuleHeader: View {
    let module: ModuleDescriptor
    @Binding var isOn: Bool
    /// The modules this one waits for, by title; empty when it runs or is off.
    var waitingFor: [String] = []

    var body: some View {
        Card(padding: Space.l) {
            HStack(spacing: Space.l) {
                IconTile(symbol: module.symbol, color: module.tint.color, size: IconSize.header)
                VStack(alignment: .leading, spacing: Space.xs) {
                    Text(module.title).font(.role(.heading, weight: .semibold))
                    Text(module.summary).font(.role(.detail)).foregroundStyle(Ink.tertiary).fixedSize(horizontal: false, vertical: true)
                    if !waitingFor.isEmpty {
                        Text("Turn on \(waitingFor.map { String(localized: "“\($0)”") }.formatted(.list(type: .and).locale(.app))) first.")
                            .font(.role(.detail)).foregroundStyle(Status.warning)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if module.canDisable {
                    RowSwitch(title: module.title, isOn: $isOn)
                } else {
                    Badge(text: String(localized: "Always On"))
                }
            }
        }
    }
}
