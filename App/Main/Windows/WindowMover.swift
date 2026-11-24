import AppKit
import ApplicationServices
import ToolsmithKit

/// Why a window could not be placed. Shown to the user as one line.
enum WindowMoveFailure: Error {
    case noPermission, noWindow, notResizable, singleDisplay, nothingToRestore

    var message: String {
        switch self {
        case .noPermission: return "창을 옮기려면 손쉬운 사용 권한이 필요합니다. 설정의 권한에서 허락해 주세요."
        case .noWindow: return "옮길 창이 없습니다."
        case .notResizable: return "이 창은 크기를 바꿀 수 없습니다."
        case .singleDisplay: return "모니터가 하나뿐입니다."
        case .nothingToRestore: return "되돌릴 이전 크기가 없습니다."
        }
    }
}

enum AccessibilityPermission {
    static var isGranted: Bool { AXIsProcessTrusted() }

    /// Shows the system's "allow in System Settings" dialog (the system decides whether to show it again).
    static func prompt() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    static func openSystemSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}

/// Moves and resizes another app's focused window through the accessibility API.
@MainActor final class WindowMover {
    /// Identifies a window for as long as it lives: its app and the accessibility element.
    private struct WindowKey: Hashable {
        let pid: pid_t
        let element: AXUIElement
        static func == (lhs: WindowKey, rhs: WindowKey) -> Bool { lhs.pid == rhs.pid && CFEqual(lhs.element, rhs.element) }
        func hash(into hasher: inout Hasher) { hasher.combine(pid); hasher.combine(CFHash(element)) }
    }

    /// The frame each window had before we first placed it, for "restore".
    private var original: [WindowKey: CGRect] = [:]
    /// The frame we last gave each window. If the window is elsewhere now, the user moved it,
    /// and that new place becomes the one to restore to.
    private var applied: [WindowKey: CGRect] = [:]

    func perform(_ action: WindowAction, on app: NSRunningApplication?, gap: CGFloat) -> Result<Void, WindowMoveFailure> {
        guard AccessibilityPermission.isGranted else {
            AccessibilityPermission.prompt()
            return .failure(.noPermission)
        }
        guard let app, let window = focusedWindow(of: app), let current = frame(of: window) else { return .failure(.noWindow) }
        let key = WindowKey(pid: app.processIdentifier, element: window)
        let screens = Self.visibleFrames()
        guard let home = Self.screen(containing: current, in: screens) else { return .failure(.noWindow) }

        let target: CGRect
        switch action {
        case .restore:
            guard let before = original[key] else { return .failure(.nothingToRestore) }
            target = before
        case .nextDisplay, .previousDisplay:
            guard screens.count > 1, let index = screens.firstIndex(of: home) else { return .failure(.singleDisplay) }
            let step = action == .nextDisplay ? 1 : screens.count - 1
            target = WindowLayout.moved(current, from: home, to: screens[(index + step) % screens.count])
        default:
            guard let computed = WindowLayout.frame(for: action, window: current, visible: home, gap: gap) else { return .failure(.noWindow) }
            target = computed
        }

        let resizable = isSettable(window, kAXSizeAttribute)
        if !resizable, target.size != current.size, action != .center, action != .nextDisplay, action != .previousDisplay {
            return .failure(.notResizable)
        }

        if action == .restore {
            original[key] = nil
            applied[key] = nil
        } else {
            if applied[key] != current { original[key] = current }
        }

        // Size, then position, then size again: a window pushed against a screen edge refuses
        // to grow until it has been moved, and may be clamped while it moves.
        if resizable { set(window, size: target.size) }
        set(window, position: target.origin)
        if resizable { set(window, size: target.size) }

        if action != .restore { applied[key] = frame(of: window) ?? target }
        prune()
        return .success(())
    }

    // MARK: Screens

    /// Usable areas (no menu bar, no Dock) in accessibility coordinates: origin at the top-left
    /// of the primary display, y downward. Ordered left to right, then top to bottom.
    static func visibleFrames() -> [CGRect] {
        guard let primary = NSScreen.screens.first else { return [] }
        let top = primary.frame.maxY
        return NSScreen.screens
            .map { CGRect(x: $0.visibleFrame.minX, y: top - $0.visibleFrame.maxY, width: $0.visibleFrame.width, height: $0.visibleFrame.height) }
            .sorted { ($0.minX, $0.minY) < ($1.minX, $1.minY) }
    }

    /// The screen showing most of the window; the nearest one if it is entirely off-screen.
    static func screen(containing window: CGRect, in screens: [CGRect]) -> CGRect? {
        func area(_ rect: CGRect) -> CGFloat { rect.isNull ? 0 : rect.width * rect.height }
        if let best = screens.max(by: { area($0.intersection(window)) < area($1.intersection(window)) }), area(best.intersection(window)) > 0 {
            return best
        }
        let center = CGPoint(x: window.midX, y: window.midY)
        return screens.min { hypot($0.midX - center.x, $0.midY - center.y) < hypot($1.midX - center.x, $1.midY - center.y) }
    }

    // MARK: Accessibility

    private func focusedWindow(of app: NSRunningApplication) -> AXUIElement? {
        let element = AXUIElementCreateApplication(app.processIdentifier)
        // An app that has stopped responding would otherwise hold the main thread for six seconds a call.
        AXUIElementSetMessagingTimeout(element, 1)
        for attribute in [kAXFocusedWindowAttribute, kAXMainWindowAttribute] {
            var value: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success, let value,
               CFGetTypeID(value) == AXUIElementGetTypeID() {
                return (value as! AXUIElement)
            }
        }
        return nil
    }

    private func frame(of window: AXUIElement) -> CGRect? {
        var positionValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &positionValue) == .success,
              AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeValue) == .success,
              let positionValue, let sizeValue,
              CFGetTypeID(positionValue) == AXValueGetTypeID(), CFGetTypeID(sizeValue) == AXValueGetTypeID() else { return nil }
        var position = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionValue as! AXValue, .cgPoint, &position),
              AXValueGetValue(sizeValue as! AXValue, .cgSize, &size) else { return nil }
        return CGRect(origin: position, size: size)
    }

    private func isSettable(_ window: AXUIElement, _ attribute: String) -> Bool {
        var settable: DarwinBoolean = false
        return AXUIElementIsAttributeSettable(window, attribute as CFString, &settable) == .success && settable.boolValue
    }

    private func set(_ window: AXUIElement, position: CGPoint) {
        var point = position
        if let value = AXValueCreate(.cgPoint, &point) { AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, value) }
    }

    private func set(_ window: AXUIElement, size: CGSize) {
        var size = size
        if let value = AXValueCreate(.cgSize, &size) { AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, value) }
    }

    /// Forgets windows of apps that have quit, so the tables do not grow forever.
    private func prune() {
        guard original.count + applied.count > 200 else { return }
        let alive = Set(NSWorkspace.shared.runningApplications.map(\.processIdentifier))
        original = original.filter { alive.contains($0.key.pid) }
        applied = applied.filter { alive.contains($0.key.pid) }
    }
}
