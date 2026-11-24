import AppKit
import Combine
import ToolsmithKit

/// The app's place in the menu bar: the items of the running modules, in the order, style and
/// grouping the user chose (`MenuBarLayout`). A left click opens what the item under the pointer
/// opens; a right click (or control-click) opens the app menu.
@MainActor final class MenuBarController {
    private unowned let environment: AppEnvironment
    /// One slot holding every item, or one slot per item, in menu bar order.
    private var slots: [Slot] = []
    private var itemSubscriptions: Set<AnyCancellable> = []
    private var subscriptions: Set<AnyCancellable> = []
    /// What the slots were built for; they are made again only when this changes.
    private var builtFor: [String] = []
    private var shownIDs: [String] = []
    /// The one panel every item opens.
    private(set) lazy var panel = MenuBarPanel(environment: environment)

    private final class Slot {
        let statusItem: NSStatusItem
        var itemIDs: [String]
        var segments: [(range: ClosedRange<CGFloat>, id: String)] = []
        var drawn: String?
        init(statusItem: NSStatusItem, itemIDs: [String]) {
            self.statusItem = statusItem
            self.itemIDs = itemIDs
        }
    }

    init(environment: AppEnvironment) {
        self.environment = environment
        // @Published announces a change before it is stored; hopping to the next main turn reads the new value.
        environment.settings.$settings.map(\.menuBarLayout).removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.rebuild() }
            .store(in: &subscriptions)
    }

    /// The app's own icon: the mark, and the app menu on a left click too.
    private lazy var appIcon = MenuBarItem(
        descriptor: .appIcon,
        glyph: { _ in AppBrand.menuBarMark.map { MenuBarGlyph(pieces: [.mark($0)], spoken: AppIdentity.name) } },
        changes: Empty().eraseToAnyPublisher(),
        click: { [weak self] frame in self?.appIconClicked(below: frame) })

    /// Every item the running modules offer, the app icon first.
    var available: [MenuBarItem] { environment.modules.menuBarItems(appIcon: appIcon) }

    /// Makes the slots again for the running modules and the saved layout.
    func rebuild() {
        let items = available
        let layout = environment.settings.settings.menuBarLayout
        let shown = layout.shown(items.map(\.descriptor))
        shownIDs = shown.map(\.id)
        let key = [layout.combined ? "combined" : "separate"] + shownIDs
        if key != builtFor {
            builtFor = key
            for slot in slots { NSStatusBar.system.removeStatusItem(slot.statusItem) }
            slots = []
            if layout.combined {
                slots = [makeSlot(shownIDs, autosave: "\(AppIdentity.bundleID).icon")]
            } else {
                // A new status item goes to the left of the ones already there: make the rightmost first.
                slots = shownIDs.reversed().map { makeSlot([$0], autosave: nil) }.reversed()
            }
        }
        itemSubscriptions = []
        let byID = Dictionary(items.map { ($0.descriptor.id, $0) }, uniquingKeysWith: { first, _ in first })
        for id in shownIDs {
            byID[id]?.changes.receive(on: DispatchQueue.main)
                .sink { [weak self] in self?.redraw() }
                .store(in: &itemSubscriptions)
        }
        let visible = Set(shownIDs)
        for module in environment.modules.running {
            module.menuBarItemsShown(Set(module.descriptor.menuBarItems.map(\.id)).intersection(visible))
        }
        for slot in slots { slot.drawn = nil }
        redraw()
    }

    private func makeSlot(_ ids: [String], autosave: String?) -> Slot {
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let autosave { statusItem.autosaveName = autosave }
        let slot = Slot(statusItem: statusItem, itemIDs: ids)
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(clicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        return slot
    }

    /// The glyphs of `ids` in `layout`'s styles; items with nothing to show are left out.
    func glyphs(_ ids: [String], layout: MenuBarLayout, items: [MenuBarItem]) -> [(id: String, glyph: MenuBarGlyph)] {
        let styles = Dictionary(layout.items(items.map(\.descriptor)).map { ($0.id, $0.style) }, uniquingKeysWith: { first, _ in first })
        let byID = Dictionary(items.map { ($0.descriptor.id, $0) }, uniquingKeysWith: { first, _ in first })
        return ids.compactMap { id in
            guard let item = byID[id], let glyph = item.glyph(styles[id] ?? item.descriptor.defaultStyle) else { return nil }
            return (id, glyph)
        }
    }

    private func redraw() {
        let items = available
        let layout = environment.settings.settings.menuBarLayout
        for slot in slots {
            var drawn = glyphs(slot.itemIDs, layout: layout, items: items)
            // Nothing to show right now (a battery reading on a Mac without one): the mark, so the slot never disappears.
            if drawn.isEmpty, let mark = appIcon.glyph(.icon) { drawn = [(MenuBarItemDescriptor.appIcon.id, mark)] }
            let signature = MenuBarRenderer.signature(drawn)
            guard signature != slot.drawn else { continue }
            slot.drawn = signature
            let output = MenuBarRenderer.draw(drawn)
            slot.segments = output.segments
            slot.statusItem.button?.image = output.image
            slot.statusItem.button?.setAccessibilityLabel(output.spoken)
        }
    }

    /// Where the app's first slot is on screen.
    var anchor: NSRect? { slots.first?.statusItem.button?.window?.frame }

    /// The menu bar as the settings preview draws it: one image per slot, for `layout`.
    func preview(_ layout: MenuBarLayout) -> [NSImage] {
        let items = available
        let ids = layout.shown(items.map(\.descriptor)).map(\.id)
        let groups = layout.combined ? [ids] : ids.map { [$0] }
        return groups.compactMap { group in
            let drawn = glyphs(group, layout: layout, items: items)
            return drawn.isEmpty ? nil : MenuBarRenderer.draw(drawn).image
        }
    }

    @objc private func clicked(_ sender: NSStatusBarButton) {
        guard let window = sender.window, let event = NSApp.currentEvent,
              let slot = slots.first(where: { $0.statusItem.button === sender }) else { return }
        if event.type == .rightMouseUp || event.modifierFlags.contains(.control) {
            environment.dismissPanels()
            showAppMenu(from: slot)
            return
        }
        // The drawing is centred in the button; find the part under the pointer.
        let x = sender.convert(event.locationInWindow, from: nil).x - (sender.bounds.width - (sender.image?.size.width ?? 0)) / 2
        let id = slot.segments.first { $0.range.contains(x) }?.id ?? slot.segments.first?.id
        let item = available.first { $0.descriptor.id == id }
        (item ?? appIcon).click(window.frame)
    }

    /// The app icon opens the panel on the screen last looked at; with no screen to show, the app menu.
    private func appIconClicked(below frame: NSRect) {
        if let id = panel.lastScreenID ?? panel.model.screens.first?.id {
            panel.toggle(id, below: frame)
        } else {
            showAppMenu()
        }
    }

    /// The app menu: the running features' lines, then settings and about, then quit, in the order macOS apps use.
    private func showAppMenu(from slot: Slot? = nil) {
        guard let slot = slot ?? slots.first, let button = slot.statusItem.button else { return }
        let menu = NSMenu()
        func add(_ title: String, _ symbol: String?, key: String = "", _ run: @escaping @MainActor () -> Void) {
            let item = NSMenuItem(title: title, action: #selector(MenuAction.run(_:)), keyEquivalent: key)
            item.keyEquivalentModifierMask = [.command]
            let action = MenuAction(run)
            item.target = action
            item.representedObject = action
            if let symbol { item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) }
            menu.addItem(item)
        }
        let entries = environment.modules.running.flatMap(\.appMenuItems)
        for entry in entries { add(entry.title, entry.symbol, entry.run) }
        if !entries.isEmpty { menu.addItem(.separator()) }
        let environment = self.environment
        add("설정…", nil, key: ",") { environment.openSettings() }
        add("\(AppIdentity.name) 정보", nil) { environment.openSettings(.about) }
        menu.addItem(.separator())
        add("\(AppIdentity.name) 종료", nil, key: "q") { NSApp.terminate(nil) }
        slot.statusItem.menu = menu
        button.performClick(nil)
        // Leave the item without a menu, so the next left click does what the item does.
        slot.statusItem.menu = nil
    }
}

/// A menu item's action as a closure. The item keeps it alive through `representedObject`.
final class MenuAction: NSObject {
    private let action: @MainActor () -> Void
    init(_ action: @escaping @MainActor () -> Void) { self.action = action }
    @MainActor @objc func run(_ sender: Any?) { action() }
}
