import AppKit
import ToolsmithKit

/// What the user is picking on screen.
enum SelectionMode {
    /// Drag out a rectangle. Space switches to picking a window.
    case area
    case window
    /// Drag out a rectangle just to read its size.
    case measure
}

enum SelectionResult {
    /// A rectangle in AppKit screen coordinates (origin bottom-left of the primary display).
    case area(CGRect)
    /// A window, with its frame in capture coordinates (origin top-left of the primary display).
    case window(id: CGWindowID, frame: CGRect)
}

/// Covers every display with a dimmed layer on which the user drags out an area or picks a window.
@MainActor final class SelectionOverlay {
    private var windows: [OverlayWindow] = []
    private var completion: ((SelectionResult?) -> Void)?

    var isActive: Bool { !windows.isEmpty }

    func begin(_ mode: SelectionMode, hint: String, canSwitchMode: Bool = false, completion: @escaping (SelectionResult?) -> Void) {
        cancel()
        self.completion = completion
        for screen in NSScreen.screens {
            let window = OverlayWindow(screen: screen, mode: mode, hint: hint, canSwitchMode: canSwitchMode) { [weak self] result in self?.finish(result) }
            windows.append(window)
            window.orderFrontRegardless()
        }
        // The overlay under the pointer takes the keyboard (esc, Space).
        let pointer = NSEvent.mouseLocation
        (windows.first { $0.frame.contains(pointer) } ?? windows.first)?.makeKey()
        NSCursor.crosshair.push()
    }

    func cancel() {
        guard isActive else { return }
        finish(nil)
    }

    private func finish(_ result: SelectionResult?) {
        guard isActive else { return }
        NSCursor.pop()
        windows.forEach { $0.orderOut(nil) }
        windows = []
        let completion = self.completion
        self.completion = nil
        completion?(result)
    }
}

private final class OverlayWindow: NSPanel {
    init(screen: NSScreen, mode: SelectionMode, hint: String, canSwitchMode: Bool, onFinish: @escaping (SelectionResult?) -> Void) {
        super.init(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        // Above everything, including the menu bar and the Dock.
        level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = false
        acceptsMouseMovedEvents = true
        isReleasedWhenClosed = false
        animationBehavior = .none
        let view = SelectionView(frame: NSRect(origin: .zero, size: screen.frame.size), screenFrame: screen.frame, mode: mode, hint: hint, canSwitchMode: canSwitchMode, onFinish: onFinish)
        contentView = view
        makeFirstResponder(view)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private final class SelectionView: NSView {
    private let screenFrame: CGRect
    private var mode: SelectionMode
    private let hint: String
    /// Whether Space may switch between dragging an area and picking a window.
    private let canSwitchMode: Bool
    private let onFinish: (SelectionResult?) -> Void
    private var dragStart: CGPoint?
    private var selection: CGRect?
    private var pointer: CGPoint?
    /// The window under the pointer, in view coordinates, with its id and capture-space frame.
    private var hovered: (rect: CGRect, id: CGWindowID, frame: CGRect)?
    private var tracking: NSTrackingArea?

    init(frame: NSRect, screenFrame: CGRect, mode: SelectionMode, hint: String, canSwitchMode: Bool, onFinish: @escaping (SelectionResult?) -> Void) {
        self.screenFrame = screenFrame
        self.mode = mode
        self.hint = hint
        self.canSwitchMode = canSwitchMode
        self.onFinish = onFinish
        super.init(frame: frame)
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("not used") }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(area)
        tracking = area
    }

    // MARK: Input

    override func mouseMoved(with event: NSEvent) {
        pointer = convert(event.locationInWindow, from: nil)
        window?.makeKey()
        if mode == .window { hovered = windowUnderPointer() }
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        pointer = nil
        hovered = nil
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if mode == .window {
            if let hovered { onFinish(.window(id: hovered.id, frame: hovered.frame)) }
            return
        }
        dragStart = point
        selection = nil
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let dragStart else { return }
        let point = convert(event.locationInWindow, from: nil)
        pointer = point
        selection = CaptureGeometry.rect(from: dragStart, to: point).intersection(bounds)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard dragStart != nil else { return }
        dragStart = nil
        guard let selection, CaptureGeometry.isUsable(selection) else {
            self.selection = nil
            needsDisplay = true
            return
        }
        onFinish(.area(selection.offsetBy(dx: screenFrame.minX, dy: screenFrame.minY)))
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53: onFinish(nil) // esc
        case 49 where canSwitchMode: // Space: area <-> window
            mode = mode == .area ? .window : .area
            selection = nil
            dragStart = nil
            hovered = mode == .window ? windowUnderPointer() : nil
            needsDisplay = true
        default: super.keyDown(with: event)
        }
    }

    override func rightMouseDown(with event: NSEvent) { onFinish(nil) }

    /// The topmost ordinary window of another app under the pointer.
    private func windowUnderPointer() -> (rect: CGRect, id: CGWindowID, frame: CGRect)? {
        guard let pointer, let primary = NSScreen.screens.first else { return nil }
        let global = CGPoint(x: pointer.x + screenFrame.minX, y: pointer.y + screenFrame.minY)
        let flipped = CGPoint(x: global.x, y: primary.frame.maxY - global.y)
        let own = ProcessInfo.processInfo.processIdentifier
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        for info in list {
            guard (info[kCGWindowLayer as String] as? Int) == 0,
                  (info[kCGWindowOwnerPID as String] as? pid_t) != own,
                  let id = info[kCGWindowNumber as String] as? CGWindowID,
                  let boundsInfo = info[kCGWindowBounds as String] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: boundsInfo), frame.contains(flipped), frame.width > 40, frame.height > 40 else { continue }
            let appKit = CGRect(x: frame.minX, y: primary.frame.maxY - frame.maxY, width: frame.width, height: frame.height)
            return (appKit.offsetBy(dx: -screenFrame.minX, dy: -screenFrame.minY), id, frame)
        }
        return nil
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let highlight = selection ?? hovered?.rect
        // Dim everything except what is being picked.
        context.setFillColor(NSColor.black.withAlphaComponent(0.28).cgColor)
        if let highlight {
            context.addRect(bounds)
            context.addRect(highlight)
            context.fillPath(using: .evenOdd)
            context.setStrokeColor(NSColor.white.withAlphaComponent(0.95).cgColor)
            context.setLineWidth(1)
            context.stroke(highlight.insetBy(dx: -0.5, dy: -0.5))
            drawLabel(CaptureGeometry.sizeLabel(highlight.size), near: highlight)
        } else {
            context.fill(bounds)
            if let pointer, mode != .window {
                // Crosshair lines to line the corner up with things on screen.
                context.setStrokeColor(NSColor.white.withAlphaComponent(0.55).cgColor)
                context.setLineWidth(1)
                context.move(to: CGPoint(x: pointer.x.rounded() + 0.5, y: 0)); context.addLine(to: CGPoint(x: pointer.x.rounded() + 0.5, y: bounds.maxY))
                context.move(to: CGPoint(x: 0, y: pointer.y.rounded() + 0.5)); context.addLine(to: CGPoint(x: bounds.maxX, y: pointer.y.rounded() + 0.5))
                context.strokePath()
            }
            drawHint()
        }
    }

    private func pill(_ text: String, size: CGFloat) -> (NSAttributedString, CGSize) {
        let string = NSAttributedString(string: text, attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: size, weight: .medium), .foregroundColor: NSColor.white,
        ])
        let textSize = string.size()
        return (string, CGSize(width: textSize.width + 16, height: textSize.height + 8))
    }

    private func drawPill(_ text: String, size: CGFloat, at origin: CGPoint) {
        let (string, pillSize) = pill(text, size: size)
        let rect = CGRect(origin: origin, size: pillSize)
        NSColor(red: 0x1C / 255, green: 0x1E / 255, blue: 0x28 / 255, alpha: 0.92).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 7, yRadius: 7).fill()
        string.draw(at: CGPoint(x: rect.minX + 8, y: rect.minY + 4))
    }

    /// The size, just below the selection (or inside it when there is no room below).
    private func drawLabel(_ text: String, near rect: CGRect) {
        let (_, size) = pill(text, size: 12)
        var origin = CGPoint(x: rect.minX, y: rect.minY - size.height - 6)
        if origin.y < 4 { origin.y = rect.minY + 6; origin.x = rect.minX + 6 }
        origin.x = min(max(origin.x, 4), bounds.maxX - size.width - 4)
        drawPill(text, size: 12, at: origin)
    }

    private func drawHint() {
        let text = mode == .window ? (canSwitchMode ? "창을 눌러 고르기 · Space 영역으로 · esc 취소" : "창을 눌러 고르기 · esc 취소")
            : (hint.isEmpty ? "끌어서 영역 고르기 · Space 창 고르기 · esc 취소" : hint)
        let (_, size) = pill(text, size: 12.5)
        drawPill(text, size: 12.5, at: CGPoint(x: bounds.midX - size.width / 2, y: bounds.maxY - size.height - 64))
    }
}
