import AppKit
import Combine
import SwiftUI
import ToolsmithKit

/// 클립보드 기록: every copy kept on this Mac, found again in the launcher or the shelf.
@MainActor final class ClipboardModule: AppModule {
    nonisolated static let descriptor = ModuleDescriptor(
        id: "clipboard", title: String(localized: "Clipboard History"), summary: String(localized: "Keeps what you copy so you can find and paste it again. Stays on this Mac"),
        symbol: "doc.on.clipboard.fill", tint: .green, permissions: [.clipboard, .accessibility],
        menuBarItems: [MenuBarItemDescriptor(id: "clipboard.icon", moduleID: "clipboard", title: String(localized: "Clipboard History"), symbol: "doc.on.clipboard",
                                             styles: [.icon], defaultVisible: false)])
    var descriptor: ModuleDescriptor { Self.descriptor }
    private unowned let host: ModuleHost
    /// nil when the history file could not be opened; the rest of the app works without it.
    let store: ClipStore?
    private let monitor = ClipboardMonitor()
    private let source: ClipboardCommandSource?
    private let shelfModel: ShelfModel?
    private(set) var shelf: ShelfPanel?
    private var purgeTimer: Timer?

    init(host: ModuleHost) {
        self.host = host
        store = try? ClipStore(directory: SettingsStore.supportDirectory.appendingPathComponent("clipboard", isDirectory: true))
        source = store.map(ClipboardCommandSource.init(store:))
        shelfModel = store.map(ShelfModel.init(store:))
        if let store, let shelfModel { shelf = ShelfPanel(model: shelfModel, store: store) }
        wire()
    }

    var commandSources: [CommandSource] { source.map { [$0] } ?? [] }
    var defaultHotkeys: [String: KeyCombo] { ClipboardCommandSource.defaultHotkeys }
    var appMenuItems: [AppMenuEntry] {
        [AppMenuEntry(title: String(localized: "Clipboard History"), symbol: "doc.on.clipboard") { [weak self] in self?.shelf?.show() }]
    }
    var menuBarItems: [MenuBarItem] {
        [.icon(Self.descriptor.menuBarItems[0]) { [weak self] frame in self?.host.openPanel(Self.descriptor.id, below: frame) }]
    }

    var panelScreens: [PanelScreen] {
        guard let store else { return [] }
        return [PanelScreen(id: Self.descriptor.id, title: String(localized: "Clipboard"), symbol: "doc.on.clipboard", settings: .clipboard, content: { [weak self] in
            AnyView(ClipboardPanelScreen(
                items: store.items(query: "", kind: nil, pinnedOnly: false, limit: ClipboardPanelScreen.count, offset: 0),
                onPaste: { item in
                    self?.host.closePanel()
                    self?.paste(item, plain: false)
                },
                onOpenShelf: {
                    self?.host.closePanel()
                    self?.shelf?.show()
                }))
        })]
    }
    func settingsGroups(in environment: AppEnvironment) -> AnyView? {
        AnyView(ClipboardPane(clipboard: self, settings: environment.settings))
    }

    private func wire() {
        guard let source, let shelf else { return }
        shelf.onPaste = { [weak self] item, plain in self?.paste(item, plain: plain) }
        shelf.bannerText = { [weak host] in
            if !ClipboardMonitor.canRead { return String(localized: "macOS is blocking clipboard access, so new copies are not recorded. See Clipboard in Settings.") }
            if host?.settings.settings.clipboardPaused == true { return String(localized: "Recording is paused.") }
            return nil
        }
        source.openShelf = { [weak self] in
            self?.host.panel.hide()
            // The same shortcut closes the shelf when it is already open.
            self?.shelf?.toggle()
        }
        source.paste = { [weak self] item in self?.paste(item, plain: false) }
        monitor.ignoredApps = { [weak host] in Set(host?.settings.settings.clipIgnoredApps ?? []) }
        monitor.isPaused = { [weak host] in host?.settings.settings.clipboardPaused ?? false }
        monitor.onImageTooLarge = { [weak host] bytes in
            // A notice takes the launcher over. If the user is already typing in it, their input matters more.
            guard let host, !host.panel.isKeyWindow else { return }
            let limit = ByteSize.text(ClipboardMonitor.maxImageBytes)
            host.notify(String(localized: "The image is larger than \(limit) (\(ByteSize.text(bytes))), so it is not kept in clipboard history. You can still paste it."))
        }
        monitor.onCopy = { [weak self] draft in
            guard let self, let store = self.store, (try? store.record(draft, at: Date())) != nil else { return }
            self.changed()
        }
    }

    func start() {
        guard let store else { return }
        monitor.start()
        store.sweepBlobs()
        purge()
        // Long-running app: apply the retention period a few times a day. Nothing else removes history
        // on its own: there is no cap on count or size, only the period the user chose and Clear All.
        let timer = Timer(timeInterval: 6 * 3_600, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.purge() }
        }
        RunLoop.main.add(timer, forMode: .common)
        purgeTimer = timer
    }

    func stop() {
        monitor.stop()
        purgeTimer?.invalidate()
        purgeTimer = nil
        shelf?.hide()
    }

    func launcherWillShow() { shelf?.hide() }
    func dismissPanels() { shelf?.hide() }

    /// The history changed: the launcher's copies and an open shelf follow.
    func changed() {
        host.commandsChanged()
        if shelf?.isShown == true { shelfModel?.reload(keepSelection: true) }
    }

    private func paste(_ item: ClipItem, plain: Bool) {
        guard let store else { return }
        guard Paster.write(item, from: store, plain: plain) else {
            host.notify(String(localized: "The contents of this item can no longer be found."))
            return
        }
        store.touch(item.id, at: Date())
        changed()
        // Give the panel a moment to let go of the keyboard, then press ⌘V for the user.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) { [weak self] in
            if !Paster.pressPaste() {
                self?.host.notify(String(localized: "Copied. Press ⌘V to paste. (With Accessibility access it pastes right away.)"))
            }
        }
    }

    func purge() {
        guard let store, let cutoff = host.settings.settings.clipRetention.cutoff(now: Date()) else { return }
        if store.purge(olderThan: cutoff) > 0 { changed() }
    }

    func clear(keepPinned: Bool) {
        store?.clearAll(keepPinned: keepPinned)
        store?.sweepBlobs()
        changed()
    }

    func stats() -> (count: Int, bytes: Int) { store?.stats() ?? (0, 0) }
}
