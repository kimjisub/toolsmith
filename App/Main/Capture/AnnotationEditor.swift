import AppKit
import SwiftUI
import ToolsmithKit

/// The state of one annotation editor window.
@MainActor final class AnnotationEditorModel: ObservableObject {
    static let lineWidths: [CGFloat] = [3, 5, 8]
    static let fontSizes: [CGFloat] = [16, 22, 30]

    let capture: CapturedImage
    @Published var document = AnnotationDocument()
    @Published var tool: AnnotationTool = .arrow
    @Published var color: AnnotationColor = .red
    /// Index into `lineWidths` and `fontSizes`.
    @Published var weight = 1
    @Published var selectedID: UUID?
    /// The annotation being dragged out, not yet part of the document.
    @Published var draft: Annotation?

    init(capture: CapturedImage) { self.capture = capture }

    var lineWidth: CGFloat { Self.lineWidths[weight] }
    var fontSize: CGFloat { Self.fontSizes[weight] }

    func deleteSelected() {
        guard let selectedID else { return }
        document.remove(selectedID)
        self.selectedID = nil
    }

    func undo() { document.undo(); selectedID = nil }
    func redo() { document.redo(); selectedID = nil }

    func rendered() -> CapturedImage {
        AnnotationRenderer.render(capture, items: document.items)
    }
}

/// The window where a capture gets its arrows, boxes, text, highlights and mosaics.
@MainActor final class AnnotationEditorWindow: NSWindow, NSWindowDelegate {
    private static var open: [AnnotationEditorWindow] = []

    private let model: AnnotationEditorModel
    private weak var canvas: AnnotationCanvasView?
    private let onCopy: (CapturedImage) -> Void
    private let onSave: (CapturedImage) -> Void

    /// The display the user is working on: the one the pointer is on.
    static var activeScreen: NSScreen? {
        let pointer = NSEvent.mouseLocation
        return NSScreen.screens.first(where: { $0.frame.contains(pointer) }) ?? NSScreen.main ?? NSScreen.screens.first
    }

    /// `screen` is where the window opens; nil means the display the pointer is on.
    static func show(_ capture: CapturedImage, on screen: NSScreen? = nil,
                     onCopy: @escaping (CapturedImage) -> Void, onSave: @escaping (CapturedImage) -> Void) {
        let target = screen ?? activeScreen
        let window = AnnotationEditorWindow(capture: capture, screen: target, onCopy: onCopy, onSave: onSave)
        open.append(window)
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        // The toolbar can make the window wider than first asked for, and the system may have its
        // own idea of where a new window goes. Put it in the middle of the intended display, last.
        window.center(on: target)
    }

    private func center(on screen: NSScreen?) {
        guard let visible = screen?.visibleFrame else { return }
        setFrameOrigin(NSPoint(x: (visible.midX - frame.width / 2).rounded(), y: (visible.midY - frame.height / 2).rounded()))
    }

    private init(capture: CapturedImage, screen: NSScreen?, onCopy: @escaping (CapturedImage) -> Void, onSave: @escaping (CapturedImage) -> Void) {
        model = AnnotationEditorModel(capture: capture)
        self.onCopy = onCopy
        self.onSave = onSave

        // The picture at its own size when it fits; scaled down to fit most of the screen otherwise.
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
        let toolbarHeight: CGFloat = 54
        let available = CGSize(width: visible.width * 0.86, height: visible.height * 0.86 - toolbarHeight)
        let zoom = min(1, available.width / capture.pointSize.width, available.height / capture.pointSize.height)
        let canvasSize = CGSize(width: (capture.pointSize.width * zoom).rounded(), height: (capture.pointSize.height * zoom).rounded())
        // Never narrower than the toolbar needs, so the window does not grow (and slide off center) after it opens.
        let content = CGSize(width: max(canvasSize.width, 790), height: canvasSize.height + toolbarHeight)

        super.init(contentRect: NSRect(x: visible.midX - content.width / 2, y: visible.midY - content.height / 2, width: content.width, height: content.height),
                   styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        title = String(localized: "Edit Annotations")
        appearance = NSAppearance(named: .darkAqua)
        isReleasedWhenClosed = false
        delegate = self

        let canvas = AnnotationCanvasView(model: model, zoom: zoom)
        canvas.frame = NSRect(origin: .zero, size: canvasSize)
        self.canvas = canvas
        let root = AnnotationEditorView(model: model, canvas: canvas, canvasSize: canvasSize, toolbarHeight: toolbarHeight,
                                        onCopy: { [weak self] in self?.copyResult() },
                                        onSave: { [weak self] in self?.saveResult() },
                                        onDone: { [weak self] in self?.done() })
        contentView = NSHostingView(rootView: root.environment(\.locale, .app))
        makeFirstResponder(canvas)
    }

    private func copyResult() {
        canvas?.commitText()
        onCopy(model.rendered())
    }

    private func saveResult() {
        canvas?.commitText()
        onSave(model.rendered())
    }

    /// Copies the result and closes: the usual way out.
    private func done() {
        copyResult()
        close()
    }

    func windowWillClose(_ notification: Notification) {
        Self.open.removeAll { $0 === self }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if canvas?.isEditingText == true { return super.performKeyEquivalent(with: event) }
        switch (flags, event.keyCode) {
        case (.command, 6): model.undo(); return true
        case ([.command, .shift], 6): model.redo(); return true
        case (.command, 8): copyResult(); return true
        case (.command, 1): saveResult(); return true
        case (.command, 13): close(); return true
        default: return super.performKeyEquivalent(with: event)
        }
    }
}

private struct AnnotationEditorView: View {
    @ObservedObject var model: AnnotationEditorModel
    let canvas: AnnotationCanvasView
    let canvasSize: CGSize
    let toolbarHeight: CGFloat
    var onCopy: () -> Void
    var onSave: () -> Void
    var onDone: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            toolbar.frame(height: toolbarHeight)
            ZStack {
                Surface.canvas
                CanvasHost(canvas: canvas).frame(width: canvasSize.width, height: canvasSize.height)
            }
        }
        .environment(\.colorScheme, .dark)
    }

    private var toolbar: some View {
        HStack(spacing: Space.m) {
            HStack(spacing: Space.xs) {
                ForEach(AnnotationTool.allCases, id: \.self) { tool in
                    Button {
                        canvas.commitText()
                        model.tool = tool
                        if tool != .select { model.selectedID = nil }
                    } label: {
                        Image(systemName: tool.symbol)
                            .font(.role(.emphasis, weight: .medium))
                            .frame(width: 34, height: 30)
                            .background(model.tool == tool ? Line.base : Color.clear, in: RoundedRectangle(cornerRadius: Radius.s, style: .continuous))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(Text(verbatim: "\(tool.title) (\(String(tool.key).uppercased()))"))
                    .accessibilityLabel(tool.title)
                    .accessibilityAddTraits(model.tool == tool ? .isSelected : [])
                }
            }
            divider
            HStack(spacing: Space.s) {
                ForEach(AnnotationColor.allCases, id: \.self) { color in
                    Button { model.color = color } label: {
                        Circle()
                            .fill(Color(nsColor: AnnotationRenderer.nsColor(color)))
                            .frame(width: 18, height: 18)
                            .overlay(Circle().strokeBorder(model.color == color ? Ink.primary : Line.strong, lineWidth: model.color == color ? 2 : 1))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(color.rawValue)
                }
            }
            divider
            Segmented(title: String(localized: "Weight"), selection: $model.weight, options: [0, 1, 2],
                      label: { [String(localized: "Thin"), String(localized: "Regular"), String(localized: "Thick")][$0] })
            .frame(width: 150)
            divider
            Button { model.undo() } label: { Image(systemName: "arrow.uturn.backward") }.disabled(!model.document.canUndo).help("Undo (⌘Z)")
            Button { model.redo() } label: { Image(systemName: "arrow.uturn.forward") }.disabled(!model.document.canRedo).help("Redo (⇧⌘Z)")
            Spacer(minLength: Space.s)
            Button("Copy", action: onCopy).help(Text(verbatim: "⌘C"))
            Button("Save", action: onSave).help(Text(verbatim: "⌘S"))
            Button("Done", action: onDone).keyboardShortcut(.defaultAction).help("Copy and Close (↵)")
        }
        .padding(.horizontal, Space.l)
        .background(Surface.canvasBar)
    }

    private var divider: some View { Fill.selected.frame(width: 1, height: 20) }
}

private struct CanvasHost: NSViewRepresentable {
    let canvas: AnnotationCanvasView
    func makeNSView(context: Context) -> AnnotationCanvasView { canvas }
    func updateNSView(_ view: AnnotationCanvasView, context: Context) { view.needsDisplay = true }
}

/// The picture being annotated. Mouse and keyboard land here.
@MainActor final class AnnotationCanvasView: NSView, NSTextFieldDelegate {
    private let model: AnnotationEditorModel
    /// Screen points per picture point (below 1 when the picture is shown smaller than life).
    private let zoom: CGFloat
    private var dragStart: CGPoint?
    /// The points of a freehand stroke being drawn.
    private var strokePoints: [CGPoint] = []
    private var moving: (id: UUID, last: CGPoint, total: CGSize)?
    private var textField: NSTextField?
    private var textOrigin: CGPoint = .zero
    private var observation: Any?

    init(model: AnnotationEditorModel, zoom: CGFloat) {
        self.model = model
        self.zoom = zoom
        super.init(frame: .zero)
        observation = model.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.needsDisplay = true }
        }
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    var isEditingText: Bool { textField != nil }

    /// Where the mouse is, in the picture's own points.
    private func point(_ event: NSEvent) -> CGPoint {
        let local = convert(event.locationInWindow, from: nil)
        return CGPoint(x: local.x / zoom, y: local.y / zoom)
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.saveGState()
        context.scaleBy(x: zoom, y: zoom)
        var items = model.document.items
        if let moving, let index = items.firstIndex(where: { $0.id == moving.id }) {
            // Show the annotation where it is being dragged to; the document changes on release.
            items[index].start.x += moving.total.width; items[index].start.y += moving.total.height
            items[index].end.x += moving.total.width; items[index].end.y += moving.total.height
        }
        if let draft = model.draft { items.append(draft) }
        AnnotationRenderer.draw(base: model.capture.image, size: model.capture.pointSize, items: items, selected: model.selectedID, in: context)
        context.restoreGState()
    }

    // MARK: Mouse

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        commitText()
        let point = point(event)
        switch model.tool {
        case .select:
            model.selectedID = model.document.hitTest(point)
            if let id = model.selectedID { moving = (id, point, .zero) }
        case .text:
            beginText(at: point)
        default:
            model.selectedID = nil
            dragStart = point
            strokePoints = [point]
        }
    }

    override func mouseDragged(with event: NSEvent) {
        let point = point(event)
        if var moving {
            moving.total.width += point.x - moving.last.x
            moving.total.height += point.y - moving.last.y
            moving.last = point
            self.moving = moving
            needsDisplay = true
        } else if let dragStart {
            var points: [CGPoint] = []
            if model.tool.isFreehand {
                // Skip points closer than a hair to the last one: they add nothing but jitter.
                if let last = strokePoints.last, hypot(point.x - last.x, point.y - last.y) >= 1.5 { strokePoints.append(point) }
                points = strokePoints
            }
            model.draft = Annotation(tool: model.tool, start: dragStart, end: point, color: model.color,
                                     lineWidth: model.lineWidth, text: "", fontSize: model.fontSize, points: points)
        }
    }

    override func mouseUp(with event: NSEvent) {
        if let moving {
            self.moving = nil
            if moving.total != .zero { model.document.move(moving.id, by: moving.total) }
            needsDisplay = true
        }
        dragStart = nil
        strokePoints = []
        if let draft = model.draft {
            model.draft = nil
            if draft.isMeaningful { model.document.add(draft) }
        }
    }

    // MARK: Text

    private func beginText(at point: CGPoint) {
        let field = NSTextField(frame: NSRect(x: point.x * zoom, y: point.y * zoom, width: max(160, bounds.width - point.x * zoom - 8), height: model.fontSize * zoom * 1.5))
        field.font = .systemFont(ofSize: model.fontSize * zoom, weight: .semibold)
        field.textColor = AnnotationRenderer.nsColor(model.color)
        field.isBordered = false
        field.drawsBackground = true
        field.backgroundColor = NSColor.black.withAlphaComponent(0.25)
        field.focusRingType = .none
        field.placeholderString = String(localized: "Type text, then ↵")
        field.delegate = self
        addSubview(field)
        textField = field
        textOrigin = point
        window?.makeFirstResponder(field)
    }

    /// Turns the text being typed into an annotation (or drops it when empty).
    func commitText() {
        guard let field = textField else { return }
        textField = nil
        let text = field.stringValue
        field.removeFromSuperview()
        let annotation = Annotation(tool: .text, start: textOrigin, end: textOrigin, color: model.color, lineWidth: model.lineWidth, text: text, fontSize: model.fontSize)
        if annotation.isMeaningful { model.document.add(annotation) }
        window?.makeFirstResponder(self)
    }

    private func cancelText() {
        textField?.removeFromSuperview()
        textField = nil
        window?.makeFirstResponder(self)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        if selector == #selector(NSResponder.insertNewline(_:)) {
            // Return during Hangul composition confirms the syllable first.
            if textView.hasMarkedText() { return false }
            commitText()
            return true
        }
        if selector == #selector(NSResponder.cancelOperation(_:)) {
            cancelText()
            return true
        }
        return false
    }

    // MARK: Keys

    /// The tools by key position (V A R P T H M), so they work in a Korean input source too.
    private static let toolKeys: [UInt16: AnnotationTool] = [9: .select, 0: .arrow, 15: .rectangle, 35: .pen, 17: .text, 4: .highlight, 46: .mosaic]

    override func keyDown(with event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        switch event.keyCode {
        case 51, 117: model.deleteSelected() // ⌫, ⌦
        case 53:
            // esc drops the selection first. It closes the window only when nothing was drawn,
            // so a stray key never throws work away.
            if model.selectedID != nil { model.selectedID = nil }
            else if model.document.items.isEmpty { window?.close() }
            else { NSSound.beep() }
        default:
            if flags.isEmpty || flags == .shift, let tool = Self.toolKeys[event.keyCode] {
                model.tool = tool
                if tool != .select { model.selectedID = nil }
            } else {
                super.keyDown(with: event)
            }
        }
    }
}
