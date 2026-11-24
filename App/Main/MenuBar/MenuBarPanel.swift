import AppKit
import Combine
import SwiftUI
import ToolsmithKit

/// What the menu bar panel shows: the screens the running modules offer, the one picked, and
/// whether the panel is pinned open.
@MainActor final class MenuBarPanelModel: ObservableObject {
    @Published var screens: [PanelScreen] = []
    @Published var selectedID: String?
    @Published var pinned = false

    var selected: PanelScreen? { screens.first { $0.id == selectedID } ?? screens.first }
}

/// The one panel under the app's menu bar items. Every module's panel screen (the system monitor,
/// the clipboard, capture, sound…) is a page of it: the panel draws the title, the switcher, the
/// pin, the way to the module's settings and the footer, and puts the picked screen below. A click
/// outside it (or esc) closes it unless it is pinned.
@MainActor final class MenuBarPanel {
    let model = MenuBarPanelModel()
    private let window = FloatingPanel()
    private unowned let environment: AppEnvironment
    /// The screen whose `onShow` ran, so `onHide` runs exactly once for it.
    private var shownID: String?
    /// The point the panel hangs from: the right edge of the item it opened under, below the menu bar.
    private var topRight = NSPoint.zero
    private var eventMonitors: [Any] = []
    private(set) var isShown = false
    /// The screen last looked at, for the app icon.
    private(set) var lastScreenID: String?

    init(environment: AppEnvironment) {
        self.environment = environment
        window.makeContent = { [weak self] in
            guard let self else { return EmptyView() }
            return MenuBarPanelView(model: self.model, panel: self, environment: self.environment)
        }
        window.onSizeChange = { [weak self] in self?.place(animated: true) }
    }

    /// The screens of the running modules, read again when modules start or stop.
    func reloadScreens() {
        model.screens = environment.modules.running.flatMap(\.panelScreens)
        guard isShown else { return }
        if model.screens.isEmpty { hide() } else if model.screens.first(where: { $0.id == shownID }) == nil { select(model.screens[0].id) }
    }

    /// Opens on `id` under `anchor`; closes when that screen is already showing.
    func toggle(_ id: String, below anchor: NSRect?) {
        if isShown, shownID == id { hide() } else { show(id, below: anchor) }
    }

    func show(_ id: String, below anchor: NSRect?) {
        guard model.screens.contains(where: { $0.id == id }) else { return }
        if isShown {
            select(id)
            return
        }
        let anchor = anchor ?? environment.menuBarAnchor() ?? NSRect(origin: NSEvent.mouseLocation, size: .zero)
        guard let screen = NSScreen.screens.first(where: { $0.frame.intersects(anchor) }) ?? NSScreen.main else { return }
        // Other floating windows (the clipboard shelf) make way.
        environment.modules.running.forEach { $0.dismissPanels() }
        isShown = true
        model.selectedID = id
        topRight = NSPoint(x: anchor.maxX, y: screen.visibleFrame.maxY - Space.xs)
        window.attach()
        place(animated: false)
        window.orderFrontRegardless()
        window.makeKey()
        startWatchingClicks()
        didShow(id)
    }

    /// Shows another screen in the open panel.
    func select(_ id: String) {
        guard isShown, id != shownID else { return }
        willHideCurrent()
        model.selectedID = id
        didShow(id)
    }

    func hide() {
        guard isShown else { return }
        isShown = false
        willHideCurrent()
        window.orderOut(nil)
        // A closed panel keeps no views: nothing redraws while it is not on screen.
        window.detach()
        eventMonitors.forEach(NSEvent.removeMonitor)
        eventMonitors = []
    }

    private func didShow(_ id: String) {
        shownID = id
        lastScreenID = id
        // The new content is laid out on the next turn; the screen hears of its window after that.
        DispatchQueue.main.async { [weak self] in
            guard let self, self.shownID == id, let screen = self.model.selected else { return }
            screen.onShow?(self.window)
        }
    }

    private func willHideCurrent() {
        guard let id = shownID else { return }
        shownID = nil
        model.screens.first { $0.id == id }?.onHide?()
    }

    /// Right-aligned under the item, top under the menu bar, inside the screen; height follows the content.
    private func place(animated: Bool) {
        guard isShown, let visible = (window.screen ?? NSScreen.main)?.visibleFrame else { return }
        let size = window.fittingSize
        let height = min(size.height, visible.height - Space.s)
        let x = min(max(topRight.x - size.width, visible.minX + Space.xs), visible.maxX - size.width - Space.xs)
        let frame = NSRect(x: x, y: topRight.y - height, width: size.width, height: height)
        guard frame != window.frame else { return }
        window.setFrame(frame, display: true, animate: animated && window.isVisible)
    }

    /// The windows that count as the panel: itself and what the screen opened beside it.
    private var ownWindows: [NSWindow] { [window] + (model.selected?.auxiliaryWindows?() ?? []) }

    private func startWatchingClicks() {
        guard eventMonitors.isEmpty else { return }
        // Clicks in other apps.
        if let global = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.model.pinned else { return }
                self.hide()
            }
        }) { eventMonitors.append(global) }
        // Clicks in this app's other windows, and esc.
        if let local = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown], handler: { [weak self] event in
            let isEscape = event.type == .keyDown && event.keyCode == 53
            let window = event.window
            let swallow = MainActor.assumeIsolated { () -> Bool in
                guard let self else { return false }
                if isEscape {
                    self.hide()
                    return true
                }
                // Menus (a picker in a screen) open their own windows; those clicks are ours too. A click
                // on a menu bar item is the item's to handle (it may be the one that closes the panel).
                if event.type != .keyDown, !self.model.pinned, let window, !self.ownWindows.contains(where: { $0 === window }),
                   !window.className.contains("Menu"), !window.className.contains("NSStatusBarWindow") {
                    self.hide()
                }
                return false
            }
            return swallow ? nil : event
        }) { eventMonitors.append(local) }
    }
}

/// The panel: the shared head, the switcher, the picked screen, the footer.
private struct MenuBarPanelView: View {
    @ObservedObject var model: MenuBarPanelModel
    let panel: MenuBarPanel
    let environment: AppEnvironment

    var body: some View {
        if let screen = model.selected {
            VStack(spacing: 0) {
                header(screen)
                if model.screens.count > 1 { switcher }
                Line.subtle.frame(height: 1)
                screen.content()
                    .frame(width: screen.width)
                    .id(screen.id)
                Line.subtle.frame(height: 1)
                footer
            }
            .frame(width: screen.width)
            .foregroundStyle(Ink.primary)
        }
    }

    private func header(_ screen: PanelScreen) -> some View {
        HStack(spacing: Space.s) {
            Image(systemName: screen.symbol).font(.role(.body, weight: .semibold)).foregroundStyle(Brand.accent)
            Text(screen.title).font(.role(.emphasis, weight: .semibold)).lineLimit(1)
            Spacer(minLength: Space.s)
            IconButton(symbol: model.pinned ? "pin.fill" : "pin", label: model.pinned ? String(localized: "Unpin") : String(localized: "Keep Open"), selected: model.pinned) {
                model.pinned.toggle()
            }
            if let pane = screen.settings {
                IconButton(symbol: "gearshape", label: String(localized: "\(screen.title) Settings")) {
                    panel.hide()
                    environment.openSettings(pane)
                }
            }
        }
        .padding(.leading, Space.l)
        .padding(.trailing, Space.s)
        .padding(.vertical, Space.s)
    }

    private var switcher: some View {
        HStack(spacing: Space.xs) {
            ForEach(model.screens) { screen in
                IconButton(symbol: screen.symbol, label: screen.title, selected: screen.id == model.selected?.id) {
                    panel.select(screen.id)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Space.s)
        .padding(.bottom, Space.s)
    }

    private var footer: some View {
        HStack(spacing: Space.xs) {
            if environment.modules.isEnabled(LauncherModule.descriptor.id) {
                FooterButton(title: String(localized: "Launcher"), symbol: "command") {
                    panel.hide()
                    environment.panel.show()
                }
            }
            Spacer()
            FooterButton(title: String(localized: "Settings"), symbol: "gearshape") {
                panel.hide()
                environment.openSettings(nil)
            }
            FooterButton(title: String(localized: "Quit"), symbol: "power") { NSApp.terminate(nil) }
        }
        .padding(.horizontal, Space.s)
        .padding(.vertical, Space.xs)
    }
}
