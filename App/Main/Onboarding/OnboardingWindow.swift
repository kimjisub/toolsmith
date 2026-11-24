import AppKit
import SwiftUI
import ToolsmithKit

/// The first-run guide's window.
@MainActor final class OnboardingWindowController: NSWindowController, NSWindowDelegate {
    let model = OnboardingModel()
    private let settings: SettingsStore

    init(settings: SettingsStore) {
        self.settings = settings
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: OnboardingView.size),
                              styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        window.title = String(localized: "Get Started with \(AppIdentity.name)")
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.appearance = NSAppearance(named: .darkAqua)
        window.isReleasedWhenClosed = false
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        super.init(window: window)
        window.delegate = self
        let host = NSHostingView(rootView: OnboardingView(model: model, settings: settings, onFinish: { [weak self] in self?.finish() }).environment(\.locale, .app))
        // The window decides the size, not the view: left to itself the view adds the title bar's height.
        host.sizingOptions = []
        window.contentView = host
        window.setContentSize(OnboardingView.size)
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("not used") }

    var isShowing: Bool { window?.isVisible == true }

    func show() {
        guard let window else { return }
        model.step = .welcome
        model.hotkeyPressed = false
        model.refresh()
        let pointer = NSEvent.mouseLocation
        if let visible = (NSScreen.screens.first(where: { $0.frame.contains(pointer) }) ?? NSScreen.main)?.visibleFrame {
            window.setFrameOrigin(NSPoint(x: (visible.midX - window.frame.width / 2).rounded(), y: (visible.midY - window.frame.height / 2).rounded()))
        }
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        #if TOOLSMITH_DEV
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            NSLog("onboarding window frame %@ content %@ scale %.2f", NSStringFromRect(window.frame), NSStringFromRect(window.contentView?.frame ?? .zero), window.backingScaleFactor)
        }
        #endif
    }

    private func finish() {
        window?.close()
    }

    /// Closing the window, by the button or the red dot, counts as done: the guide is not forced on anyone twice.
    func windowWillClose(_ notification: Notification) {
        settings.update { $0.onboardingCompleted = true }
    }
}
