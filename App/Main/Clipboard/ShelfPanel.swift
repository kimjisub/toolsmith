import AppKit
import SwiftUI
import ToolsmithKit

/// The window of the clipboard shelf. Like the launcher it takes the keyboard without becoming
/// the frontmost app, so pasting goes to the app the user was in.
@MainActor final class ShelfPanel: NSPanel {
    static let height: CGFloat = 330

    private let model: ShelfModel
    private let presentation = ShelfPresentation()
    private var hideWork: DispatchWorkItem?
    /// Paste this entry into the app in front. `plain` leaves formatting out.
    var onPaste: ((ClipItem, _ plain: Bool) -> Void)?
    /// Asked each time the shelf opens: the reason nothing is being recorded, if any.
    var bannerText: () -> String? = { nil }

    init(model: ShelfModel, store: ClipStore) {
        self.model = model
        super.init(contentRect: NSRect(x: 0, y: 0, width: 900, height: Self.height),
                   styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView], backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        hidesOnDeactivate = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        animationBehavior = .none
        isReleasedWhenClosed = false

        let view = ShelfView(model: model, presentation: presentation, store: store,
                             onCommand: { [weak self] in self?.handle($0) },
                             onPick: { [weak self] id in
                                 self?.model.select(id)
                                 self?.pasteSelected(plain: false)
                             })
        let host = NSHostingView(rootView: view.environment(\.locale, .app))
        host.sizingOptions = []
        contentView = host
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    var isShown: Bool { isVisible && presentation.isShown }

    func toggle() {
        if isShown { hide() } else { show() }
    }

    func show() {
        hideWork?.cancel()
        let pointer = NSEvent.mouseLocation
        guard var screen = NSScreen.screens.first(where: { $0.frame.contains(pointer) }) ?? NSScreen.main ?? NSScreen.screens.first else { return }
        // Development aid, for capturing the shelf on a known display.
        if CommandLine.arguments.contains("--primary-screen"), let primary = NSScreen.screens.first { screen = primary }
        let visible = screen.visibleFrame
        setFrame(NSRect(x: visible.minX, y: visible.minY, width: visible.width, height: Self.height), display: true)

        model.reset()
        presentation.banner = bannerText()
        orderFrontRegardless()
        makeKey()
        focusField()
        presentation.isShown = true
    }

    func hide() {
        guard isVisible else { return }
        model.endUndo()
        presentation.isShown = false
        hideWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.orderOut(nil) }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Theme.disappear, execute: work)
    }

    private func handle(_ command: QueryCommand) {
        switch command {
        case .left, .up: model.move(by: -1)
        case .right, .down: model.move(by: 1)
        case .tab: model.cycleFilter()
        case .cancel: hide()
        case .deleteEmpty, .backTab: break
        case .submit:
            let shift = NSApp.currentEvent?.modifierFlags.contains(.shift) ?? false
            pasteSelected(plain: shift)
        case .number(let number):
            guard let item = model.item(number: number) else { return }
            hide()
            onPaste?(item, false)
        }
    }

    private func pasteSelected(plain: Bool) {
        guard let item = model.selected else { return }
        hide()
        onPaste?(item, plain)
    }

    private func focusField() {
        func find(_ view: NSView) -> NSTextField? {
            if let field = view as? QueryTextField { return field }
            for child in view.subviews { if let found = find(child) { return found } }
            return nil
        }
        if let contentView, let field = find(contentView) { makeFirstResponder(field) }
    }

    private static let numberKeys: [UInt16: Int] = [18: 1, 19: 2, 20: 3, 21: 4, 23: 5, 22: 6, 26: 7, 28: 8, 25: 9]

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags == .command else { return super.performKeyEquivalent(with: event) }
        if let number = Self.numberKeys[event.keyCode] {
            handle(.number(number))
            return true
        }
        switch event.keyCode {
        case 35: model.togglePin(); return true          // ⌘P
        case 51: model.deleteSelected(); return true     // ⌘⌫
        case 6: model.undoDelete(); return true          // ⌘Z
        case 12, 13, 4, 46: return true                  // ⌘Q, ⌘W, ⌘H, ⌘M were meant for the app behind
        case 0: return NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: self)
        case 9: return NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: self)
        default: return super.performKeyEquivalent(with: event)
        }
    }

    override func cancelOperation(_ sender: Any?) { hide() }

    override func resignKey() {
        super.resignKey()
        hide()
    }
}
