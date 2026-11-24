import AppKit
import SwiftUI
import ToolsmithKit

/// Settings → Menu Bar: a preview of the real menu bar on top, then whether the items share one
/// slot, then every item of the running features: drag to order, a style, a switch.
struct MenuBarPane: View {
    @ObservedObject var environment: AppEnvironment
    @ObservedObject var modules: ModuleManager
    @ObservedObject var settings: SettingsStore
    private static let rowHeight: CGFloat = 46
    private static let styleColumn: CGFloat = 132

    private var layout: MenuBarLayout { settings.settings.menuBarLayout }
    private var available: [MenuBarItemDescriptor] { environment.menuBar.available.map(\.descriptor) }

    var body: some View {
        let items = layout.items(available)
        SettingsPage(title: String(localized: "Menu Bar"), lead: String(localized: "Choose what the features you turned on show in the menu bar. The top of the list is the left of the menu bar. Click an item to open its feature; right-click for the app menu.")) {
            preview
            SettingsSection(footer: layout.combined
                            ? String(localized: "All items sit side by side in one menu bar slot. Clicking opens the item under the pointer.")
                            : String(localized: "Each item gets its own menu bar slot, in the order of this list.")) {
                ToggleRow(title: String(localized: "Combine into One Slot"), detail: String(localized: "When off, each item gets its own slot"), isOn: Binding(
                    get: { layout.combined },
                    set: { on in settings.update { $0.menuBarLayout.combined = on } }))
            }
            VStack(alignment: .leading, spacing: Space.s) {
                Text("Items").font(.role(.body, weight: .semibold)).padding(.leading, Space.xs)
                List {
                    ForEach(items, id: \.id) { item in
                        row(item)
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    }
                    .onMove { source, destination in
                        settings.update { $0.menuBarLayout.move(fromOffsets: source, toOffset: destination, among: available) }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .scrollDisabled(true)
                .frame(height: CGFloat(items.count) * Self.rowHeight)
                .background(Fill.card, in: RoundedRectangle(cornerRadius: Radius.m, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Radius.m, style: .continuous).strokeBorder(Line.subtle, lineWidth: 1))
                Text("Drag to reorder. If nothing is shown, the app icon appears on its own. Items of features that are off come back here when you turn them on.")
                    .font(.role(.detail)).foregroundStyle(Ink.tertiary).padding(.horizontal, Space.xs).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// The menu bar as it will look, redrawn every second with live readings.
    private var preview: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            let images = environment.menuBar.preview(layout).map(MenuBarPreview.flatten)
            HStack(spacing: 0) {
                Spacer(minLength: Space.m)
                HStack(spacing: layout.combined ? 0 : 12) {
                    ForEach(Array(images.enumerated()), id: \.offset) { _, image in
                        Image(nsImage: image).interpolation(.high)
                    }
                }
                .padding(.horizontal, Space.s)
                .padding(.vertical, Space.xs)
                .background(Fill.control, in: RoundedRectangle(cornerRadius: Radius.xs, style: .continuous))
                HStack(spacing: Space.l) {
                    Image(systemName: "wifi")
                    Image(systemName: "switch.2")
                    Text(Date.now.formatted(.dateTime.month().day().weekday().hour().minute()))
                }
                .font(.role(.secondary, weight: .medium))
                .foregroundStyle(Ink.tertiary)
                .padding(.leading, Space.l)
                .padding(.trailing, Space.m)
            }
            .frame(height: 30)
            .frame(maxWidth: .infinity)
            .background(LinearGradient(colors: [Surface.menuBarTop, Surface.menuBarBottom], startPoint: .top, endPoint: .bottom),
                        in: RoundedRectangle(cornerRadius: Radius.s, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Radius.s, style: .continuous).strokeBorder(Line.base, lineWidth: 1))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Menu Bar Preview")
        }
    }

    private func row(_ item: MenuBarLayout.Item) -> some View {
        let module = modules.module(id: item.descriptor.moduleID)?.descriptor
        return HStack(spacing: Space.m) {
            Image(systemName: "line.3.horizontal")
                .font(.role(.secondary, weight: .medium))
                .foregroundStyle(Ink.disabled)
                .accessibilityHidden(true)
            IconTile(symbol: item.descriptor.symbol, color: module?.tint.color ?? Tile.gray)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.descriptor.title).font(.role(.body))
                Text(module?.title ?? AppIdentity.name).font(.role(.detail)).foregroundStyle(Ink.tertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            // One column for the style, so every switch lines up; an item with one style names it there.
            Group {
                if item.descriptor.styles.count > 1 {
                    RowMenu(title: String(localized: "Style"), selection: Binding(get: { item.style }, set: { style in
                        settings.update { $0.menuBarLayout.setStyle(item.id, style, among: available) }
                    }), options: item.descriptor.styles, label: \.label)
                    .disabled(!item.visible)
                } else {
                    Text(item.style.label).font(.role(.secondary)).foregroundStyle(Ink.disabled)
                }
            }
            .frame(width: Self.styleColumn, alignment: .trailing)
            .padding(.trailing, Space.s)
            RowSwitch(title: item.descriptor.title, isOn: Binding(get: { item.visible }, set: { on in
                settings.update { $0.menuBarLayout.setVisible(item.id, on, among: available) }
            }))
        }
        .padding(.horizontal, Space.l)
        .frame(height: Self.rowHeight)
        .overlay(alignment: .bottom) { Line.subtle.frame(height: 1).padding(.leading, Space.l) }
    }
}

/// Menu bar images as they look on a dark menu bar. Template images are tinted white there; the
/// others draw their words in the menu bar's text color, resolved now for the dark appearance.
enum MenuBarPreview {
    static func flatten(_ image: NSImage) -> NSImage {
        let size = image.size
        let flat = NSImage(size: size)
        flat.lockFocus()
        NSAppearance(named: .darkAqua)?.performAsCurrentDrawingAppearance {
            image.draw(in: NSRect(origin: .zero, size: size))
            if image.isTemplate {
                NSColor.white.withAlphaComponent(0.92).set()
                NSRect(origin: .zero, size: size).fill(using: .sourceAtop)
            }
        }
        flat.unlockFocus()
        return flat
    }
}
