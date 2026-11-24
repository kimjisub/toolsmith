import AppKit
import SwiftUI
import ToolsmithKit

/// The launcher while a snippet's variables are filled in: the snippet's name, a field per
/// variable, and the text exactly as it will be pasted.
struct SnippetFillView: View {
    @ObservedObject var model: LauncherModel
    let fill: SnippetFill
    /// The tallest the whole launcher card may be.
    var maxHeight: CGFloat
    var onCommand: (QueryCommand) -> Void

    /// How the launcher tells the fields apart when it hands out the keyboard.
    static func focusKey(session: UUID, index: Int) -> String { "\(session.uuidString):\(index)" }

    private static let headerHeight: CGFloat = 64
    private static let hintHeight: CGFloat = 34
    private static let listPadding: CGFloat = 8
    private static let labelRole = TextRole.body
    private static let previewRole = TextRole.body
    /// A variable's name gets as much room as the longest one needs, up to this.
    private static let maxLabelWidth: CGFloat = 200

    private var variables: [SnippetTemplate.Variable] { fill.template.variables }
    private var emptyCount: Int { fill.values.filter(\.isEmpty).count }
    /// The preview's own height, so its part of the card is no taller than the text.
    @State private var previewHeight: CGFloat = 0

    /// Wide enough for the longest name, so the values line up in one column.
    private var labelWidth: CGFloat {
        let font = NSFont.role(Self.labelRole)
        let widest = variables.map { ($0.name as NSString).size(withAttributes: [.font: font]).width }.max() ?? 0
        return min(Self.maxLabelWidth, widest.rounded(.up) + 2)
    }

    /// The fields and the preview share what is left of the card. Each scrolls when it needs more.
    private var bodyHeight: CGFloat { max(160, maxHeight - Self.headerHeight - Self.hintHeight - 2) }
    private var fieldsHeight: CGFloat {
        min(CGFloat(variables.count) * Theme.rowHeight + Self.listPadding * 2, (bodyHeight * 0.55).rounded())
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Line.subtle.frame(height: 1)
            ScrollView { fields }
                .scrollIndicators(.never)
                .frame(height: fieldsHeight)
            Line.subtle.frame(height: 1)
            ScrollView {
                preview.onGeometryChange(for: CGFloat.self) { $0.size.height } action: { previewHeight = $0 }
            }
            .scrollIndicators(.never)
            .frame(height: min(max(previewHeight, 1), bodyHeight - fieldsHeight))
            hint
        }
    }

    private var header: some View {
        HStack(spacing: Space.m) {
            CommandIconView(icon: .symbol("text.quote"))
            Text(fill.name)
                .font(.role(Theme.queryRole, weight: .medium))
                .foregroundStyle(Ink.primary)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Space.xl)
        .frame(height: Self.headerHeight)
    }

    private var fields: some View {
        VStack(spacing: 0) {
            ForEach(Array(variables.enumerated()), id: \.offset) { index, variable in
                field(index, variable)
            }
        }
        .padding(Self.listPadding)
    }

    private func field(_ index: Int, _ variable: SnippetTemplate.Variable) -> some View {
        let focused = fill.focus == index
        return HStack(spacing: Space.xl) {
            Text(variable.name)
                .font(.role(Self.labelRole))
                .foregroundStyle(focused ? Ink.secondary : Ink.tertiary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: labelWidth, alignment: .leading)
            QueryField(text: Binding(get: { model.fill.flatMap { $0.values.indices.contains(index) ? $0.values[index] : nil } ?? "" },
                                     set: { model.setFillValue($0, at: index) }),
                       role: Theme.rowRole, fontWeight: .regular, capturesTab: true,
                       caretColor: NSColor.white.withAlphaComponent(0.9),
                       textColor: NSColor.white.withAlphaComponent(0.94),
                       focusKey: Self.focusKey(session: fill.session, index: index),
                       accessibilityLabel: String(localized: "Value for \(variable.name)"),
                       onFocus: { model.setFillFocus(index) }, onCommand: onCommand)
        }
        .padding(.horizontal, Space.l)
        .frame(height: Theme.rowHeight)
        .background {
            // The same mark as the selected row of the results: the whole row, filled and lit.
            if focused {
                RoundedRectangle(cornerRadius: Radius.m, style: .continuous)
                    .fill(Fill.selected)
                    .overlay(RoundedRectangle(cornerRadius: Radius.m, style: .continuous).strokeBorder(Tint.light(Brand.glow), lineWidth: 1))
                    .shadow(color: Tint.light(Brand.glow), radius: 11)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { model.setFillFocus(index) }
    }

    /// The text as it will be pasted. What the user typed is bright and bold, what was filled in
    /// automatically is bright, and a variable still empty shows its name, dim and underlined.
    private var preview: some View {
        Text(previewText)
            .font(.role(Self.previewRole))
            .lineSpacing(7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Space.xl)
            .padding(.top, Space.l)
            .padding(.bottom, Space.xl)
    }

    private var previewText: AttributedString {
        var text = AttributedString()
        for run in fill.preview {
            var part = AttributedString(run.text)
            switch run.kind {
            case .plain:
                part.foregroundColor = Ink.secondary
            case .filled:
                part.foregroundColor = Ink.primary
                part.font = .role(Self.previewRole, weight: .semibold)
            case .pending:
                part.foregroundColor = Ink.tertiary
                part.underlineStyle = Text.LineStyle(pattern: .dash, color: Ink.disabled)
            }
            text.append(part)
        }
        return text
    }

    private var hint: some View {
        HStack(spacing: Space.xs) {
            if emptyCount > 0 { Text("\(emptyCount) empty fields · ↵ pastes with them left blank") }
            Spacer()
            KeyCap(label: "⇥")
            Text("Next Field")
            KeyCap(label: "↵").padding(.leading, Space.s)
            Text("Paste")
            KeyCap(label: "esc").padding(.leading, Space.s)
            Text(fill.returnsToList ? "Back" : "Close")
        }
        .font(.role(.detail))
        .foregroundStyle(Ink.tertiary)
        .padding(.horizontal, Space.xl)
        .frame(height: Self.hintHeight)
        .background(Shade.soft)
    }
}
