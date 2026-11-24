import AppKit
import Combine
import SwiftUI
import ToolsmithKit

/// The launcher window. A non-activating panel: it takes the keyboard without making the app
/// the frontmost app, so the app the user was in stays the target of whatever they run.
@MainActor final class LauncherPanel: NSPanel, QueryFieldHost {
    static let width: CGFloat = Theme.panelWidth
    /// Room around the card for its shadow and glow.
    private static let margin: CGFloat = 70

    private let model: LauncherModel
    private let presentation = LauncherPresentation()
    private let ai: AISession
    /// The OpenRouter key, asked at the moment of asking.
    var aiKey: () -> String? = { nil }
    /// Called when a question is asked with no key: open the settings where it goes.
    var onNeedsAIKey: (() -> Void)?
    /// The app that was frontmost just before the launcher opened.
    private(set) var previousApp: NSRunningApplication?
    /// Called just before the panel appears.
    var onWillShow: (() -> Void)?
    /// ⌘, pressed while the launcher is open.
    var onOpenSettings: (() -> Void)?
    /// Called just before a command picked in the launcher runs.
    var onWillRun: (() -> Void)?
    /// A snippet's fields were filled in and Return pressed: the text, and the app it is for
    /// (the one in front when the launcher opened).
    var onSubmitFill: ((String, NSRunningApplication?) -> Void)?
    private var hideWork: DispatchWorkItem?
    private var subscriptions: Set<AnyCancellable> = []

    init(model: LauncherModel, settings: SettingsStore, ai: AISession) {
        self.model = model
        self.ai = ai
        super.init(contentRect: NSRect(x: 0, y: 0, width: Self.width + Self.margin * 2, height: 600),
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

        let view = LauncherView(
            model: model, settings: settings, presentation: presentation, ai: ai,
            hasAIKey: { KeyStore.isAvailable },
            onCommand: { [weak self] in self?.handle($0) },
            onPick: { [weak self] id in self?.run(id) }
        )
        .padding(.top, Self.margin)
        let host = NSHostingView(rootView: view)
        host.sizingOptions = []
        contentView = host

        // Which field has the keyboard follows the model: the query field, or the field of the
        // snippet variable in focus. Published values arrive before they are set, hence the hop.
        model.$fill.map { _ in () }.merge(with: model.$mode.map { _ in () })
            .sink { [weak self] in DispatchQueue.main.async { self?.applyFocus() } }
            .store(in: &subscriptions)
    }

    /// Runs a command picked in the launcher (Return, ⌘number, a click). The launcher closes
    /// first, unless the command goes on inside it.
    private func run(_ id: String) {
        if model.command(id: id)?.keepsLauncherOpen != true { hide() }
        onWillRun?()
        model.activate(id: id)
    }

    /// Brings the launcher up as a snippet's fill screen, or as the snippet search (a global
    /// shortcut). `begin` starts it. An open launcher changes in place: what was typed and asked there is dropped, and
    /// the app it was opened over stays the target. "Open" is what the user sees, not `isVisible`,
    /// which is still true while the panel fades out.
    func showForFill(_ begin: () -> Void) {
        let open = isOpen
        hideWork?.cancel()
        presentation.notice = nil
        if open {
            ai.clear()
            model.reset()
            begin()
            if !isKeyWindow { makeKey() }
        } else {
            show()
            begin()
        }
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    var isShown: Bool { isVisible && presentation.isShown }
    /// The launcher itself is up, taking keys. Not so while only a notice is shown: a notice
    /// has no keyboard and no app it was opened over.
    var isOpen: Bool { isShown && presentation.notice == nil }

    func toggle() {
        // While a notice is up, the shortcut opens the launcher rather than dismissing the notice.
        if isShown, presentation.notice == nil { hide() } else { show() }
    }

    /// Shows one line where the launcher appears, for a moment, without taking the keyboard.
    func showNotice(_ text: String) {
        hideWork?.cancel()
        guard place() else { return }
        // The launcher may still hold the keyboard on its way out. A notice must not: let go of
        // it first (which schedules a hide), then cancel that hide and show.
        if isKeyWindow { orderOut(nil) }
        hideWork?.cancel()
        presentation.notice = text
        orderFrontRegardless()
        presentation.isShown = true
        let work = DispatchWorkItem { [weak self] in self?.hide() }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.6, execute: work)
    }

    func show() {
        hideWork?.cancel()
        presentation.notice = nil
        ai.clear()
        let started = CFAbsoluteTimeGetCurrent()
        defer {
            // The budget from key press to a visible window is 100 ms; this is our share of it.
            if CommandLine.arguments.contains("--show-launcher") {
                NSLog("launcher show took %.1f ms", (CFAbsoluteTimeGetCurrent() - started) * 1000)
            }
        }
        previousApp = NSWorkspace.shared.frontmostApplication
        onWillShow?()
        model.reset()

        guard place() else { return }

        orderFrontRegardless()
        makeKey()
        focusField()
        presentation.isShown = true
    }

    /// Puts the panel on the screen the pointer is on: centered, the card's top a quarter of the
    /// way down. False when there is no display to show on.
    private func place() -> Bool {
        let pointer = NSEvent.mouseLocation
        // No display at all (lid closed, nothing attached): there is nowhere to show.
        guard var screen = NSScreen.screens.first(where: { $0.frame.contains(pointer) }) ?? NSScreen.main ?? NSScreen.screens.first else { return false }
        // Development aid, for capturing the launcher on a known display.
        if CommandLine.arguments.contains("--primary-screen"), let primary = NSScreen.screens.first { screen = primary }
        let visible = screen.visibleFrame
        let cardMax = (visible.height * 0.6).rounded()
        presentation.maxHeight = cardMax
        let size = NSSize(width: Self.width + Self.margin * 2, height: cardMax + Self.margin * 2)
        let cardTop = visible.maxY - (visible.height * 0.25).rounded()
        setFrame(NSRect(x: (visible.midX - size.width / 2).rounded(), y: cardTop + Self.margin - size.height,
                        width: size.width, height: size.height), display: true)
        return true
    }

    func hide() {
        guard isVisible else { return }
        ai.stop()
        presentation.isShown = false
        hideWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.orderOut(nil) }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Theme.disappear, execute: work)
    }

    private func handle(_ command: QueryCommand) {
        if model.mode == .fill {
            handleFill(command)
            return
        }
        switch command {
        case .up: model.moveSelection(by: -1)
        case .down: model.moveSelection(by: 1)
        case .cancel:
            // esc steps back one thing at a time: a flowing answer, then AI mode, then the launcher.
            if ai.isStreaming {
                ai.stop()
            } else if model.mode == .ai {
                ai.clear()
                model.exitAIMode()
            } else if model.mode == .snippets {
                // Back to the commands the search was picked from, or out when a shortcut opened it.
                if model.exitSnippetSearch() == .close { hide() }
            } else {
                hide()
            }
        case .left, .right, .backTab: break // the launcher leaves these to the text field
        case .tab: model.selectAIRow()
        case .deleteEmpty:
            // ⌫ in the empty AI field goes back to commands, unless an answer is on screen.
            if model.mode == .ai, ai.isEmpty { model.exitAIMode() }
            // The same in the empty snippet search, when there are commands to go back to.
            if model.mode == .snippets, model.snippetSearchReturnsToList { model.exitSnippetSearch() }
        case .submit:
            if model.mode == .ai || model.selectedID == LauncherModel.aiRowID {
                ask()
                return
            }
            // With no results nothing is selected and Return does nothing: the window stays.
            guard let id = model.selectedID else { return }
            run(id)
        case .number(let number):
            let ids = model.visibleIDs
            guard number >= 1, number <= ids.count else { return }
            run(ids[number - 1])
        }
    }

    /// Keys while a snippet's variables are being filled in.
    private func handleFill(_ command: QueryCommand) {
        switch command {
        case .tab: model.moveFillFocus(by: 1)
        case .backTab: model.moveFillFocus(by: -1)
        case .submit:
            guard let text = model.submitFill() else { return }
            let target = previousApp
            hide()
            onSubmitFill?(text, target)
        case .cancel:
            // Back to the results the snippet was picked from, or out when a shortcut opened this.
            if model.cancelFill() == .close { hide() }
        case .up, .down, .left, .right, .deleteEmpty, .number: break
        }
    }

    /// Sends the question. This is the only place typed text leaves the Mac.
    private func ask() {
        guard !ai.isStreaming, case .ask(let question) = model.submit() else {
            if model.mode == .ai, !KeyStore.isAvailable, model.query.trimmingCharacters(in: .whitespaces).isEmpty { onNeedsAIKey?() }
            return
        }
        guard let key = aiKey() else {
            onNeedsAIKey?()
            return
        }
        model.enterAIMode() // the field empties and now takes follow-up questions
        ai.ask(question, key: key)
    }

    private func focusField() { applyFocus() }

    /// The key of the field that should have the keyboard: nil for the query field.
    private var wantedFocusKey: String? {
        guard model.mode == .fill, let fill = model.fill else { return nil }
        return SnippetFillView.focusKey(session: fill.session, index: fill.focus)
    }

    /// Gives the keyboard to the field the model points at, if it is on screen and does not
    /// have it already. A field that is not there yet gets it when it attaches.
    private func applyFocus() {
        func find(_ view: NSView, key: String?) -> QueryTextField? {
            if let field = view as? QueryTextField, field.focusKey == key { return field }
            for child in view.subviews { if let found = find(child, key: key) { return found } }
            return nil
        }
        guard let contentView, let field = find(contentView, key: wantedFocusKey) else { return }
        // Taking the keyboard again would select the text and drop a syllable being composed.
        if (firstResponder as? NSTextView)?.delegate !== field { makeFirstResponder(field) }
        field.scrollToVisible(field.bounds)
    }

    func queryFieldDidAttach(_ field: QueryTextField) {
        if field.focusKey == wantedFocusKey { applyFocus() }
    }

    /// Key positions of 1…9 (the same whichever input source is active).
    private static let numberKeys: [UInt16: Int] = [18: 1, 19: 2, 20: 3, 21: 4, 23: 5, 22: 6, 26: 7, 28: 8, 25: 9]

    // While the launcher has the keyboard, ⌘ keys come to the app rather than the app behind.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags == .command else { return super.performKeyEquivalent(with: event) }
        if let number = Self.numberKeys[event.keyCode] {
            handle(.number(number)) // ⌘1…⌘9 run the numbered row (nothing while a snippet is filled in)
            return true
        }
        switch event.keyCode {
        case 43:
            // ⌘, opens settings, as it does in any Mac app. Only here: as a global shortcut it
            // would take ⌘, away from every other app.
            onOpenSettings?()
            return true
        case 12, 13, 4, 46:
            // ⌘Q, ⌘W, ⌘H, ⌘M were meant for the app behind. Quitting the app here would be a
            // surprise, so they do nothing.
            return true
        case 0: return NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: self)
        case 8:
            // ⌘C copies the answer, unless some text in the window is selected.
            let editor = firstResponder as? NSTextView
            if model.mode == .ai, (editor?.selectedRange.length ?? 0) == 0, let answer = ai.lastAnswer {
                NSPasteboard.general.clearContents()
                // As it reads on screen, without the markdown marks.
                NSPasteboard.general.setString(String(AIAnswerView.formatted(answer).characters), forType: .string)
                return true
            }
            return NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: self)
        case 9: return NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: self)
        case 7: return NSApp.sendAction(#selector(NSText.cut(_:)), to: nil, from: self)
        case 6: return NSApp.sendAction(Selector(("undo:")), to: nil, from: self)
        default: return super.performKeyEquivalent(with: event)
        }
    }

    override func cancelOperation(_ sender: Any?) { hide() }

    // A click anywhere else takes key status away: that closes the launcher.
    override func resignKey() {
        super.resignKey()
        hide()
    }
}
