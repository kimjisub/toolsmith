import AppKit
import ToolsmithKit

/// Captures a page taller than the screen: scrolls the area a step at a time, takes a picture after
/// each step, and joins the pictures where they overlap.
@MainActor final class ScrollCapturer {
    static let maxFrames = 60
    /// A stitched picture taller than this is cut off; it is already far more than a page.
    static let maxPixelHeight = 20_000

    private(set) var isRunning = false
    private var cancelled = false
    private var escMonitor: Any?

    /// Ends the capture with what has been taken so far.
    func finishEarly() { cancelled = true }

    /// `area` is in AppKit screen coordinates.
    func run(area: CGRect) async throws -> CapturedImage {
        guard !isRunning else { throw CaptureError.failed(String(localized: "A scrolling capture is already running.")) }
        // Scrolling for the user means sending scroll events, which needs the Accessibility permission.
        guard AccessibilityPermission.isGranted else {
            AccessibilityPermission.prompt()
            throw CaptureError.failed(String(localized: "Scrolling capture needs Accessibility permission to scroll for you. Allow it in General in Settings."))
        }
        guard let primary = NSScreen.screens.first else { throw CaptureError.failed(String(localized: "There is no display.")) }
        isRunning = true
        cancelled = false
        escMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { Task { @MainActor in self?.finishEarly() } }
        }
        defer {
            isRunning = false
            if let escMonitor { NSEvent.removeMonitor(escMonitor) }
            escMonitor = nil
        }

        // The pointer must be over the area for the scroll to go there.
        let center = CGPoint(x: area.midX, y: primary.frame.maxY - area.midY)
        let pointerBefore = NSEvent.mouseLocation
        defer { CGWarpMouseCursorPosition(CGPoint(x: pointerBefore.x, y: primary.frame.maxY - pointerBefore.y)) }
        CGWarpMouseCursorPosition(center)
        try? await Task.sleep(for: .milliseconds(150))

        let first = try await Capturer.area(area)
        let scale = first.scale
        var previousRows = Self.rowHashes(first.image)
        var plan = ScrollStitch.Plan(frameHeight: first.image.height)
        var pieces: [CGImage] = [first.image]
        // Less than half the area per step, so consecutive pictures always overlap.
        let step = max(40, Int(area.height * 0.4))

        for _ in 1..<Self.maxFrames {
            if cancelled || plan.totalHeight >= Self.maxPixelHeight { break }
            Self.scroll(by: step, at: center)
            try? await Task.sleep(for: .milliseconds(320))
            let frame = try await Capturer.area(area)
            guard frame.image.height == first.image.height, frame.image.width == first.image.width else { break }
            let rows = Self.rowHashes(frame.image)
            // nil: the page changed in a way we cannot follow. 0: the end of the page.
            guard let shift = ScrollStitch.shift(previous: previousRows, next: rows), shift > 0,
                  let range = plan.append(shift: shift),
                  let piece = frame.image.cropping(to: CGRect(x: 0, y: range.lowerBound, width: frame.image.width, height: range.count)) else { break }
            pieces.append(piece)
            previousRows = rows
        }

        guard let stitched = Self.stack(pieces) else { throw CaptureError.failed(String(localized: "Couldn’t stitch the pieces together.")) }
        return CapturedImage(image: stitched, scale: scale)
    }

    private static func scroll(by points: Int, at location: CGPoint) {
        // Negative is "content moves up", i.e. scrolling down the page.
        guard let event = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: Int32(-points), wheel2: 0, wheel3: 0) else { return }
        event.location = location
        event.post(tap: .cghidEventTap)
    }

    /// One number per pixel row, from the middle of the row (the right edge has the scroll bar, which moves).
    static func rowHashes(_ image: CGImage) -> [UInt64] {
        let width = image.width, height = image.height
        guard width > 0, height > 0,
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return [] }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let data = context.data else { return [] }
        let pixels = data.bindMemory(to: UInt32.self, capacity: width * height)
        let from = width / 20, to = max(from + 1, width - max(width / 10, 48))
        var hashes = [UInt64](repeating: 0, count: height)
        for row in 0..<height {
            var hash: UInt64 = 1_469_598_103_934_665_603
            var column = from
            while column < to {
                hash = (hash ^ UInt64(pixels[row * width + column])) &* 1_099_511_628_211
                column += 2
            }
            hashes[row] = hash
        }
        return hashes
    }

    /// Stacks pictures of the same width top to bottom.
    private static func stack(_ pieces: [CGImage]) -> CGImage? {
        guard let width = pieces.first?.width else { return nil }
        let height = min(pieces.reduce(0) { $0 + $1.height }, maxPixelHeight)
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        var top = height
        for piece in pieces {
            top -= piece.height
            if top + piece.height <= 0 { break }
            context.draw(piece, in: CGRect(x: 0, y: top, width: width, height: piece.height))
        }
        return context.makeImage()
    }
}
