import AppKit
import SwiftUI

enum QueryCommand: Equatable {
    case up, down, submit, cancel
    /// ←, → and Tab, reported only when the field is asked to give them up (`capturesNavigation`).
    case left, right, tab
    /// ⇧Tab, reported only when Tab is (`capturesTab`).
    case backTab
    /// ⌫ pressed in an already empty field.
    case deleteEmpty
    case number(Int)
}

/// The launcher's text field. SwiftUI's TextField hides what a Korean launcher needs: the
/// syllable still being composed, and whether Return is confirming that syllable or running a command.
struct QueryField: NSViewRepresentable {
    @Binding var text: String
    var role: TextRole
    var fontWeight: NSFont.Weight = .medium
    /// When true, ←, → and Tab move through results instead of moving the caret.
    var capturesNavigation = false
    /// When true, Tab is reported instead of moving focus.
    var capturesTab = false
    var caretColor: NSColor = .white
    /// The colour the field draws its own text in. Clear where a SwiftUI overlay draws the glyphs
    /// instead (the query field, for its gradient).
    var textColor: NSColor = .clear
    /// Tells this field apart from the others in the window, for giving it the keyboard.
    var focusKey: String?
    var accessibilityLabel = String(localized: "What would you like to do?")
    /// Called when the field takes the keyboard (a click on it).
    var onFocus: (() -> Void)?
    var onCommand: (QueryCommand) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> QueryTextField {
        let field = QueryTextField()
        field.delegate = context.coordinator
        field.isBordered = false
        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = .none
        // Same weight as the overlay that draws the glyphs, or the caret drifts away from the text.
        field.font = .role(role, weight: fontWeight)
        // The glyphs are drawn by a SwiftUI overlay (a gradient); the field supplies caret and editing.
        field.textColor = textColor
        field.focusKey = focusKey
        field.onFocus = onFocus
        field.cell?.usesSingleLineMode = true
        field.cell?.wraps = false
        field.cell?.isScrollable = true
        field.setAccessibilityLabel(accessibilityLabel)
        // The text is there from the start (a variable's default), not only after an update.
        field.stringValue = text
        return field
    }

    func updateNSView(_ field: QueryTextField, context: Context) {
        context.coordinator.parent = self
        field.focusKey = focusKey
        field.onFocus = onFocus
        // Never overwrite the field while the user is composing: that would drop the syllable.
        let editor = field.currentEditor() as? NSTextView
        if editor?.hasMarkedText() != true, (editor?.string ?? field.stringValue) != text {
            // Text changed from outside (reset, the leading "." that switches to AI being dropped).
            // While the field is being edited its editor holds the text, so that is what must change.
            field.stringValue = text
            if let editor {
                editor.string = text
                editor.selectedRange = NSRange(location: (text as NSString).length, length: 0)
            }
        }
        field.caretColor = caretColor
        editor?.insertionPointColor = caretColor
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: QueryField
        init(_ parent: QueryField) { self.parent = parent }

        func controlTextDidChange(_ notification: Notification) {
            // The field editor's string includes marked (still composing) text.
            let editor = notification.userInfo?["NSFieldEditor"] as? NSTextView
            let value = editor?.string ?? (notification.object as? NSTextField)?.stringValue ?? ""
            if parent.text != value { parent.text = value }
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            switch selector {
            case #selector(NSResponder.insertNewline(_:)):
                // The Korean input method commits the syllable first and then forwards this Return,
                // so the query already holds the whole word and one Return runs it. An input method
                // that sends Return with the text still marked only wants it committed.
                if textView.hasMarkedText() { return false }
                parent.onCommand(.submit)
                return true
            case #selector(NSResponder.moveUp(_:)):
                parent.onCommand(.up)
                return true
            case #selector(NSResponder.moveDown(_:)):
                parent.onCommand(.down)
                return true
            case #selector(NSResponder.cancelOperation(_:)):
                parent.onCommand(.cancel)
                return true
            case #selector(NSResponder.moveLeft(_:)) where parent.capturesNavigation:
                parent.onCommand(.left)
                return true
            case #selector(NSResponder.moveRight(_:)) where parent.capturesNavigation:
                parent.onCommand(.right)
                return true
            case #selector(NSResponder.insertTab(_:)) where parent.capturesNavigation || parent.capturesTab:
                parent.onCommand(.tab)
                return true
            case #selector(NSResponder.insertBacktab(_:)) where parent.capturesTab:
                parent.onCommand(.backTab)
                return true
            case #selector(NSResponder.deleteBackward(_:)) where textView.string.isEmpty:
                parent.onCommand(.deleteEmpty)
                return true
            default:
                return false
            }
        }
    }
}

/// A window that decides which of its query fields has the keyboard.
@MainActor protocol QueryFieldHost: AnyObject {
    func queryFieldDidAttach(_ field: QueryTextField)
}

final class QueryTextField: NSTextField {
    var caretColor: NSColor = .white
    var focusKey: String?
    var onFocus: (() -> Void)?

    // SwiftUI makes a field after the state that wants it focused has changed. The window is
    // told when the field arrives, so the keyboard can go to it then.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        (window as? QueryFieldHost)?.queryFieldDidAttach(self)
    }

    override func becomeFirstResponder() -> Bool {
        let became = super.becomeFirstResponder()
        if became { onFocus?() }
        if let editor = currentEditor() as? NSTextView {
            let caret = caretColor
            editor.insertionPointColor = caret
            editor.markedTextAttributes = [.underlineStyle: NSUnderlineStyle.single.rawValue, .underlineColor: caret.withAlphaComponent(0.6)]
            editor.selectedTextAttributes = [.backgroundColor: NSColor.white.withAlphaComponent(0.18)]
        }
        return became
    }
}

/// The query field as it looks everywhere in the app: gradient glyphs, a placeholder, a peach caret.
struct GradientQueryField: View {
    @Binding var text: String
    var placeholder: String
    var role: TextRole
    var capturesNavigation = false
    var capturesTab = false
    /// The lavender-to-peach gradient marks a question for the AI. Ordinary typing is plain white.
    var gradient = false
    var onCommand: (QueryCommand) -> Void

    private static let peach = NSColor(red: 1, green: 0xC9 / 255, blue: 0xA3 / 255, alpha: 1)

    var body: some View {
        ZStack(alignment: .leading) {
            if text.isEmpty {
                Text(placeholder)
                    .font(.role(role, weight: .medium))
                    .foregroundStyle(Ink.tertiary)
                    .padding(.leading, Space.xs)
            } else {
                // The field's own glyphs are clear; this draws them with the gradient. The 2pt inset
                // matches the field editor's line padding so the caret sits right after the text.
                Text(text)
                    .font(.role(role, weight: .medium))
                    .foregroundStyle(gradient ? AnyShapeStyle(Brand.gradient) : AnyShapeStyle(Ink.primary))
                    .lineLimit(1)
                    .padding(.leading, Space.xs)
                    .fixedSize()
                    .allowsHitTesting(false)
            }
            QueryField(text: $text, role: role, capturesNavigation: capturesNavigation, capturesTab: capturesTab,
                       caretColor: gradient ? Self.peach : NSColor.white.withAlphaComponent(0.9), onCommand: onCommand)
        }
    }
}
