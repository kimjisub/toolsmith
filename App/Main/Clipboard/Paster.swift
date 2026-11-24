import AppKit
import ToolsmithKit

/// Puts a history entry back on the clipboard and pastes it into the app in front.
@MainActor enum Paster {
    private static let marker = NSPasteboard.PasteboardType(ClipboardPolicy.ownMarker)

    /// Writes `item` to the system clipboard. `plain` leaves out the formatted form of a text.
    /// False when the entry's content is gone (a missing image file).
    @discardableResult static func write(_ item: ClipItem, from store: ClipStore, plain: Bool) -> Bool {
        let pasteboard = NSPasteboard.general
        switch item.kind {
        case .text, .link:
            guard let text = item.text else { return false }
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)
            if !plain, let url = store.blobURL(for: item), let rich = try? Data(contentsOf: url) {
                pasteboard.setData(rich, forType: .rtf)
            }
        case .image:
            guard let url = store.blobURL(for: item), let data = try? Data(contentsOf: url) else { return false }
            pasteboard.clearContents()
            pasteboard.setData(data, forType: .png)
            if let tiff = NSImage(data: data)?.tiffRepresentation { pasteboard.setData(tiff, forType: .tiff) }
        case .file:
            let urls = item.fileURLs.map { URL(fileURLWithPath: $0) as NSURL }
            guard !urls.isEmpty else { return false }
            pasteboard.clearContents()
            pasteboard.writeObjects(urls)
        }
        // So the monitor knows this change is ours and does not record it as a new copy.
        pasteboard.setData(Data(), forType: marker)
        return true
    }

    /// Puts plain text on the clipboard (a filled-in snippet), marked as ours so the clipboard
    /// history does not record it as a new copy.
    static func write(text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        pasteboard.setData(Data(), forType: marker)
    }

    /// Presses ⌘V only while `target` is still the app in front. False when it is not, or
    /// without the Accessibility permission: then nothing was pressed.
    @discardableResult static func pressPaste(into target: NSRunningApplication?) -> Bool {
        let frontmost = NSWorkspace.shared.frontmostApplication?.processIdentifier
        guard SnippetPaste.shouldPress(target: target?.processIdentifier, frontmost: frontmost) else { return false }
        return pressPaste()
    }

    /// Presses ⌘V for the user. Needs the Accessibility permission; false without it.
    @discardableResult static func pressPaste() -> Bool {
        guard AccessibilityPermission.isGranted, let source = CGEventSource(stateID: .combinedSessionState) else { return false }
        let vKey: CGKeyCode = 9
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: false) else { return false }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cgAnnotatedSessionEventTap)
        up.post(tap: .cgAnnotatedSessionEventTap)
        return true
    }
}
