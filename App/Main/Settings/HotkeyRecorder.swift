import AppKit
import ToolsmithKit

/// What the user did while a shortcut row was waiting for a key.
enum RecordedKey: Equatable {
    case combo(KeyCombo)
    /// ⌫ alone: remove the shortcut.
    case clear
    /// esc alone: leave things as they were.
    case cancel
}

/// Listens for one key press while the settings window is recording a shortcut.
@MainActor final class HotkeyRecorder {
    private var monitor: Any?

    var isRecording: Bool { monitor != nil }

    /// Takes the next key pressed in `window`. Keys typed anywhere else pass through untouched.
    func start(in window: NSWindow?, _ handler: @escaping (RecordedKey) -> Void) {
        stop()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self, weak window] event in
            guard let self, let window, event.window === window else { return event }
            let key = Self.recorded(from: event)
            self.stop()
            handler(key)
            return nil // the key belongs to the recorder, not to the window
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    static func recorded(from event: NSEvent) -> RecordedKey {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var modifiers: KeyModifiers = []
        if flags.contains(.control) { modifiers.insert(.control) }
        if flags.contains(.option) { modifiers.insert(.option) }
        if flags.contains(.shift) { modifiers.insert(.shift) }
        if flags.contains(.command) { modifiers.insert(.command) }
        if modifiers.isEmpty, event.keyCode == 53 { return .cancel }
        if modifiers.isEmpty, event.keyCode == 51 { return .clear }
        return .combo(KeyCombo(keyCode: event.keyCode, modifiers: modifiers))
    }
}
