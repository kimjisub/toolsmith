import AppKit
import SwiftUI

/// A borderless glass panel that takes the keyboard without activating the app, and reports when
/// its content wants a different size.
final class FloatingPanel: NSPanel {
    var onSizeChange: (() -> Void)?
    /// Builds the content each time the panel is shown.
    var makeContent: (() -> any View)?
    private var host: SizeReportingHostingView<AnyView>?

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 340, height: 400),
                   styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView], backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        hidesOnDeactivate = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        animationBehavior = .none
        isReleasedWhenClosed = false
    }

    func attach() {
        guard host == nil, let view = makeContent?() else { return }
        let host = SizeReportingHostingView(rootView: AnyView(AnyView(view).glassSurface(corner: Radius.l).environment(\.locale, .app)))
        host.sizingOptions = [.intrinsicContentSize]
        host.onInvalidate = { [weak self] in
            DispatchQueue.main.async { self?.onSizeChange?() }
        }
        self.host = host
        contentView = host
    }

    func detach() {
        host = nil
        contentView = nil
    }

    var fittingSize: NSSize { host?.fittingSize ?? frame.size }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

final class SizeReportingHostingView<Content: View>: NSHostingView<Content> {
    var onInvalidate: (() -> Void)?

    override func invalidateIntrinsicContentSize() {
        super.invalidateIntrinsicContentSize()
        onInvalidate?()
    }
}
