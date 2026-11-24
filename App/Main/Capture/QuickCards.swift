import AppKit
import SwiftUI
import ToolsmithKit

/// A capture waiting in the corner of the screen for the user to do something with it.
struct QuickCard: Identifiable {
    let id = UUID()
    let capture: CapturedImage
    /// The picture as a file, so the card can be dragged into another app.
    let fileURL: URL?
    var saved = false
}

@MainActor final class QuickCardModel: ObservableObject {
    static let limit = 4
    @Published var cards: [QuickCard] = []
}

/// The stack of recent captures in the bottom-left corner.
@MainActor final class QuickCardPanel: NSPanel {
    let model = QuickCardModel()
    var onCopy: ((QuickCard) -> Void)?
    var onSave: ((QuickCard) -> URL?)?
    var onPin: ((QuickCard) -> Void)?
    var onText: ((QuickCard) -> Void)?
    /// The card to edit, and the display the card is on (the editor opens there).
    var onEdit: ((QuickCard, NSScreen?) -> Void)?

    static let cardSize = CGSize(width: 228, height: 150)

    init() {
        super.init(contentRect: .zero, styleMask: [.nonactivatingPanel, .borderless], backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        hidesOnDeactivate = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        let host = NSHostingView(rootView: QuickCardStack(model: model, panel: self).environment(\.locale, .app))
        host.sizingOptions = []
        contentView = host
    }

    override var canBecomeKey: Bool { false }

    /// `png` is the picture already encoded (encoding a large capture is slow; it is done once, off the main thread).
    func add(_ capture: CapturedImage, png: Data?) {
        // Written to a scratch folder so the card can be dragged out as a file.
        var fileURL: URL?
        if let data = png {
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent("\(AppIdentity.bundleID).captures", isDirectory: true)
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let url = CaptureFileName.uniqueURL(in: folder, name: CaptureFileName.name(date: Date(), ext: "png"))
            if (try? data.write(to: url)) != nil { fileURL = url }
        }
        model.cards.append(QuickCard(capture: capture, fileURL: fileURL))
        if model.cards.count > QuickCardModel.limit {
            let pushedOut = model.cards.prefix(model.cards.count - QuickCardModel.limit)
            pushedOut.forEach(Self.removeFile)
            model.cards.removeFirst(pushedOut.count)
        }
        layout()
    }

    func close(_ id: UUID) {
        model.cards.filter { $0.id == id }.forEach(Self.removeFile)
        model.cards.removeAll { $0.id == id }
        layout()
    }

    /// The scratch file exists only for dragging; a capture is private, so it goes with its card.
    /// (A drag has already copied the file by then.)
    private static func removeFile(_ card: QuickCard) {
        if let url = card.fileURL { try? FileManager.default.removeItem(at: url) }
    }

    func markSaved(_ id: UUID) {
        if let index = model.cards.firstIndex(where: { $0.id == id }) { model.cards[index].saved = true }
    }

    private func layout() {
        guard !model.cards.isEmpty else {
            orderOut(nil)
            return
        }
        let pointer = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(pointer) }) ?? NSScreen.main ?? NSScreen.screens.first else { return }
        let count = CGFloat(model.cards.count)
        let height = count * Self.cardSize.height + (count - 1) * 10 + 40
        setFrame(NSRect(x: screen.visibleFrame.minX, y: screen.visibleFrame.minY, width: Self.cardSize.width + 40, height: height), display: true)
        orderFrontRegardless()
    }
}

private struct QuickCardStack: View {
    @ObservedObject var model: QuickCardModel
    weak var panel: QuickCardPanel?

    var body: some View {
        VStack(spacing: Space.m) {
            ForEach(model.cards) { card in
                QuickCardView(card: card, panel: panel)
            }
        }
        .padding(Space.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        .environment(\.colorScheme, .dark)
    }
}

private struct QuickCardView: View {
    let card: QuickCard
    weak var panel: QuickCardPanel?
    @State private var hovering = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.l, style: .continuous)
        ZStack {
            Image(nsImage: card.capture.nsImage)
                .resizable()
                .scaledToFit()
                .padding(Space.s)
                .frame(width: QuickCardPanel.cardSize.width, height: QuickCardPanel.cardSize.height)
            if hovering {
                Shade.strong
                VStack(spacing: Space.s) {
                    HStack(spacing: Space.s) {
                        button(String(localized: "Copy"), "doc.on.doc") { panel?.onCopy?(card) }
                        button(card.saved ? String(localized: "Saved") : String(localized: "Save"), card.saved ? "checkmark" : "square.and.arrow.down") {
                            if panel?.onSave?(card) != nil { panel?.markSaved(card.id) }
                        }
                    }
                    HStack(spacing: Space.s) {
                        button(String(localized: "Edit"), "pencil.tip.crop.circle") { panel?.onEdit?(card, panel?.screen) }
                        button(String(localized: "Pin"), "pin") { panel?.onPin?(card); panel?.close(card.id) }
                        button(String(localized: "Text"), "text.viewfinder") { panel?.onText?(card) }
                    }
                }
                VStack {
                    HStack {
                        Spacer()
                        Button { panel?.close(card.id) } label: {
                            Image(systemName: "xmark").font(.role(.caption, weight: .bold)).frame(width: 20, height: 20)
                                .background(Line.base, in: Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Close")
                    }
                    Spacer()
                }
                .padding(Space.s)
            }
        }
        .frame(width: QuickCardPanel.cardSize.width, height: QuickCardPanel.cardSize.height)
        .glassSurface(corner: 14)
        .clipShape(shape)
        .shadow(color: Shade.strong, radius: 14, y: 6)
        .onHover { hovering = $0 }
        .onDrag {
            guard let url = card.fileURL else { return NSItemProvider() }
            return NSItemProvider(contentsOf: url) ?? NSItemProvider()
        }
    }

    private func button(_ title: String, _ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: Space.xs) {
                Image(systemName: symbol).font(.role(.caption, weight: .semibold))
                Text(title).font(.role(.detail, weight: .medium))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, Space.s)
            .padding(.vertical, Space.xs)
            .background(Line.base, in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// A capture kept floating above other windows, to look at while working elsewhere.
@MainActor final class PinWindow: NSPanel {
    private static var open: [PinWindow] = []

    static func show(_ capture: CapturedImage) {
        let window = PinWindow(capture: capture)
        open.append(window)
        window.orderFrontRegardless()
    }

    private init(capture: CapturedImage) {
        // Shown at the size it had on screen, but never larger than most of the display.
        var size = capture.pointSize
        if let visible = NSScreen.main?.visibleFrame {
            let fit = min(1, visible.width * 0.8 / size.width, visible.height * 0.8 / size.height)
            size = CGSize(width: size.width * fit, height: size.height * fit)
        }
        let pointer = NSEvent.mouseLocation
        super.init(contentRect: NSRect(x: pointer.x - size.width / 2, y: pointer.y - size.height / 2, width: size.width, height: size.height),
                   styleMask: [.nonactivatingPanel, .borderless, .resizable], backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        hidesOnDeactivate = false
        isMovableByWindowBackground = true
        hasShadow = true
        isReleasedWhenClosed = false
        contentAspectRatio = size
        let view = PinImageView(image: capture.nsImage) { [weak self] in self?.dismiss() }
        view.frame = NSRect(origin: .zero, size: size)
        contentView = view
    }

    override var canBecomeKey: Bool { true }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { dismiss() } else { super.keyDown(with: event) }
    }

    private func dismiss() {
        orderOut(nil)
        Self.open.removeAll { $0 === self }
    }
}

private final class PinImageView: NSImageView {
    private let onClose: () -> Void

    init(image: NSImage, onClose: @escaping () -> Void) {
        self.onClose = onClose
        super.init(frame: .zero)
        self.image = image
        imageScaling = .scaleProportionallyUpOrDown
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.masksToBounds = true
        toolTip = String(localized: "Double-click or press esc to close")
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("not used") }

    override var mouseDownCanMoveWindow: Bool { true }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 { onClose() } else { super.mouseDown(with: event) }
    }
}
