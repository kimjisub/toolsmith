import AppKit
import ToolsmithKit

/// Watches the system clipboard and turns each new copy into a `ClipDraft`.
@MainActor final class ClipboardMonitor {
    /// Larger copies are not kept: a history entry should not cost tens of megabytes. An image over the limit is reported (`onImageTooLarge`).
    nonisolated static let maxImageBytes = 25_000_000
    static let maxTextCharacters = 1_000_000
    static let maxRichBytes = 2_000_000

    var onCopy: ((ClipDraft) -> Void)?
    /// An image was copied but is too large to keep; called with its size in bytes.
    var onImageTooLarge: ((Int) -> Void)?
    /// Current settings, asked at each copy.
    var ignoredApps: () -> Set<String> = { [] }
    var isPaused: () -> Bool = { false }

    private var timer: Timer?
    private var pending: Task<Void, Never>?
    private var lastChangeCount = NSPasteboard.general.changeCount

    /// Whether macOS lets us read what other apps copied without asking the user each time.
    /// With "ask" every read would raise a system alert, so we do not read at all.
    static var canRead: Bool {
        switch NSPasteboard.general.accessBehavior {
        case .ask, .alwaysDeny: return false
        default: return true
        }
    }

    func start() {
        guard timer == nil else { return }
        // What was copied while the history was off stays unrecorded.
        lastChangeCount = NSPasteboard.general.changeCount
        // The pasteboard has no change notification; comparing its change count is the supported way.
        let timer = Timer(timeInterval: 0.4, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.check() }
        }
        timer.tolerance = 0.1
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        pending?.cancel()
        pending = nil
    }

    private func check() {
        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount != lastChangeCount else { return }
        lastChangeCount = pasteboard.changeCount
        guard Self.canRead else { return }

        let types = (pasteboard.types ?? []).map(\.rawValue)
        // The login window is "frontmost" while the screen is locked or nothing has focus; it did not copy anything.
        let frontmost = NSWorkspace.shared.frontmostApplication
        let source = frontmost?.bundleIdentifier == "com.apple.loginwindow" ? nil : frontmost
        guard ClipboardPolicy.shouldRecord(types: types, sourceBundleID: source?.bundleIdentifier,
                                           ignoredApps: ignoredApps(), paused: isPaused()) else { return }
        switch Self.read(pasteboard, source: source) {
        case .draft(let draft):
            deliver { .draft(draft) }
        case .imageTooLarge(let bytes):
            deliver { .imageTooLarge(bytes) }
        case .image(let raw, let isPNG):
            let bundleID = source?.bundleIdentifier, name = source?.localizedName
            deliver { await Self.imageDraft(raw: raw, isPNG: isPNG, bundleID: bundleID, name: name) }
        case nil:
            break
        }
    }

    /// Hands copies to `onCopy` in the order they were made, even when one (an image) takes a while.
    private func deliver(_ make: @escaping @Sendable () async -> Copied?) {
        let previous = pending
        pending = Task { [weak self] in
            await previous?.value
            switch await make() {
            case .draft(let draft): self?.onCopy?(draft)
            case .imageTooLarge(let bytes): self?.onImageTooLarge?(bytes)
            case .image, nil: break
            }
        }
    }

    enum Copied {
        case draft(ClipDraft)
        /// An image as it came off the pasteboard; decoding it is slow and happens off the main thread.
        case image(Data, isPNG: Bool)
        /// An image over the limit, with its size. It stays on the clipboard; only the history skips it.
        case imageTooLarge(Int)
    }

    /// Files first, then text (with its formatted form), then a bare image.
    static func read(_ pasteboard: NSPasteboard, source: NSRunningApplication?) -> Copied? {
        let bundleID = source?.bundleIdentifier
        let name = source?.localizedName

        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty {
            return .draft(ClipDraft(kind: .file, text: nil, data: nil, fileURLs: urls.map(\.path), sourceBundleID: bundleID, sourceName: name, width: nil, height: nil))
        }
        if let string = pasteboard.string(forType: .string), !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            guard string.count <= maxTextCharacters else { return nil }
            var rich = pasteboard.data(forType: .rtf)
            if let data = rich, data.count > maxRichBytes { rich = nil }
            return .draft(ClipDraft(kind: ClipboardPolicy.kind(forText: string), text: string, data: rich, fileURLs: [],
                                    sourceBundleID: bundleID, sourceName: name, width: nil, height: nil))
        }
        if let png = pasteboard.data(forType: .png) {
            return png.count <= maxImageBytes ? .image(png, isPNG: true) : .imageTooLarge(png.count)
        }
        // TIFF is uncompressed, so it may be several times the PNG it becomes.
        if let tiff = pasteboard.data(forType: .tiff) {
            return tiff.count <= maxImageBytes * 4 ? .image(tiff, isPNG: false) : .imageTooLarge(tiff.count)
        }
        return nil
    }

    /// Always stored as PNG, whatever form it was copied in.
    private nonisolated static func imageDraft(raw: Data, isPNG: Bool, bundleID: String?, name: String?) async -> Copied? {
        await Task.detached(priority: .utility) { () -> Copied? in
            guard let bitmap = NSBitmapImageRep(data: raw),
                  let data = isPNG ? raw : bitmap.representation(using: .png, properties: [:]) else { return nil }
            guard data.count <= maxImageBytes else { return .imageTooLarge(data.count) }
            return .draft(ClipDraft(kind: .image, text: nil, data: data, fileURLs: [], sourceBundleID: bundleID, sourceName: name,
                             width: bitmap.pixelsWide, height: bitmap.pixelsHigh))
        }.value
    }
}
