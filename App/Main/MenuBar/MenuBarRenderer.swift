import AppKit
import ToolsmithKit

/// Draws menu bar items into one image: each item's pieces side by side, items a little further
/// apart. Used for the real menu bar and for the preview in the settings, so both look the same.
enum MenuBarRenderer {
    struct Output {
        let image: NSImage
        /// Which part of the image (x range, in points) belongs to which item.
        let segments: [(range: ClosedRange<CGFloat>, id: String)]
        let spoken: String
    }

    static let height: CGFloat = 22
    static let barCount = 24
    private static let itemGap: CGFloat = 5
    private static let pieceGap: CGFloat = 2
    private static let font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
    private static let lineFont = NSFont.monospacedDigitSystemFont(ofSize: 12.5, weight: .medium)
    private static let symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 13.5, weight: .medium)

    /// Everything the image shows, at the precision it shows it: an image is redrawn only when this changes.
    static func signature(_ items: [(id: String, glyph: MenuBarGlyph)]) -> String {
        items.map { item in
            item.id + ":" + item.glyph.pieces.map { piece -> String in
                switch piece {
                case .mark: return "mark"
                case .symbol(let name): return "s" + name
                case .text(let text), .label(let text): return text
                case .bars(let lower, let upper): return (lower + upper).map { MonitorText.whole($0 * 12) }.joined(separator: ",")
                case .level(let value, _): return MonitorText.whole(value * 12)
                case .mirror(let above, let below, _, _): return (above + below).map { MonitorText.whole($0 * 6) }.joined(separator: ",")
                case .stack(let top, let bottom): return top + "/" + bottom
                }
            }.joined(separator: ";")
        }.joined(separator: "|")
    }

    static func draw(_ items: [(id: String, glyph: MenuBarGlyph)]) -> Output {
        var layout: [(MenuBarPiece, CGFloat)] = []
        var segments: [(range: ClosedRange<CGFloat>, id: String)] = []
        var x: CGFloat = 0
        for (number, item) in items.enumerated() {
            if number > 0 { x += itemGap }
            let start = x
            for (index, piece) in item.glyph.pieces.enumerated() {
                if index > 0 { x += pieceGap }
                layout.append((piece, x))
                x += width(of: piece)
            }
            segments.append((start - itemGap / 2...x + itemGap / 2, item.id))
        }
        let image = NSImage(size: NSSize(width: ceil(max(x, 1)), height: height), flipped: false) { rect in
            for (piece, x) in layout { draw(piece, at: x, in: rect) }
            return true
        }
        // Words and symbols alone are a template, tinted by the menu bar (and white when it is highlighted).
        image.isTemplate = layout.allSatisfy { $0.0.isMonochrome }
        let spoken = ([AppIdentity.name] + items.map(\.glyph.spoken)).joined(separator: ", ")
        return Output(image: image, segments: segments, spoken: spoken)
    }

    private static func symbolImage(_ name: String) -> NSImage? {
        NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(symbolConfiguration)
    }

    private static func width(of piece: MenuBarPiece) -> CGFloat {
        switch piece {
        case .mark(let image): return image.size.width
        case .symbol(let name): return ceil(symbolImage(name)?.size.width ?? 16)
        case .text(let text): return ceil((text as NSString).size(withAttributes: [.font: lineFont]).width)
        case .label: return 7
        case .bars, .mirror: return CGFloat(barCount) + 3
        case .level: return 8
        case .stack(let top, let bottom):
            return ceil([top, bottom].map { ($0 as NSString).size(withAttributes: [.font: font]).width }.max() ?? 0)
        }
    }

    /// Strong blue and red read at menu bar size: blue for the main flow (user CPU, reads,
    /// downloads, memory), red for the other (system CPU, writes, uploads).
    static let blue = NSColor(srgbRed: 0.16, green: 0.52, blue: 1, alpha: 1)
    static let red = NSColor(srgbRed: 1, green: 0.22, blue: 0.36, alpha: 1)
    static let green = NSColor(srgbRed: 0.20, green: 0.82, blue: 0.42, alpha: 1)

    private static func draw(_ piece: MenuBarPiece, at x: CGFloat, in rect: NSRect) {
        let box = NSRect(x: x, y: 1, width: width(of: piece), height: rect.height - 2)
        switch piece {
        case .mark(let image):
            image.draw(in: NSRect(x: x, y: (rect.height - image.size.height) / 2, width: image.size.width, height: image.size.height))
        case .symbol(let name):
            guard let base = symbolImage(name) else { return }
            let image = base.withSymbolConfiguration(NSImage.SymbolConfiguration(paletteColors: [.labelColor])) ?? base
            image.draw(in: NSRect(x: x, y: ((rect.height - base.size.height) / 2).rounded(), width: base.size.width, height: base.size.height))
        case .text(let text):
            let attributes: [NSAttributedString.Key: Any] = [.font: lineFont, .foregroundColor: NSColor.labelColor]
            let size = (text as NSString).size(withAttributes: attributes)
            (text as NSString).draw(at: NSPoint(x: x, y: ((rect.height - size.height) / 2).rounded()), withAttributes: attributes)
        case .label(let text):
            let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 6.8, weight: .bold), .foregroundColor: NSColor.labelColor]
            let letters = Array(text)
            let line: CGFloat = 6.9
            let top = rect.midY + line * CGFloat(letters.count) / 2
            for (index, letter) in letters.enumerated() {
                let string = String(letter) as NSString
                let size = string.size(withAttributes: attributes)
                string.draw(at: NSPoint(x: x + (box.width - size.width) / 2, y: top - line * CGFloat(index + 1) - 0.8), withAttributes: attributes)
            }
        case .bars(let lower, let upper):
            let inside = frame(box)
            let slot = inside.width / CGFloat(barCount)
            let count = min(lower.count, barCount)
            for index in 0..<count {
                let base = inside.minX + CGFloat(barCount - count + index) * slot
                let a = inside.height * clamp(lower[lower.count - count + index])
                let b = min(inside.height - a, inside.height * clamp(index < upper.count ? upper[upper.count - count + index] : 0))
                blue.setFill()
                NSRect(x: base, y: inside.minY, width: slot, height: a).fill()
                red.setFill()
                NSRect(x: base, y: inside.minY + a, width: slot, height: b).fill()
            }
        case .level(let value, let color):
            let inside = frame(box)
            color.setFill()
            NSBezierPath(roundedRect: NSRect(x: inside.minX, y: inside.minY, width: inside.width, height: inside.height * clamp(value)), xRadius: 1.2, yRadius: 1.2).fill()
        case .mirror(let above, let below, let aboveColor, let belowColor):
            let inside = frame(box)
            NSColor.labelColor.withAlphaComponent(0.3).setFill()
            NSRect(x: inside.minX, y: inside.midY - 0.25, width: inside.width, height: 0.5).fill()
            bars(above, in: NSRect(x: inside.minX, y: inside.midY, width: inside.width, height: inside.height / 2), color: aboveColor, upward: true)
            bars(below, in: NSRect(x: inside.minX, y: inside.minY, width: inside.width, height: inside.height / 2), color: belowColor, upward: false)
        case .stack(let top, let bottom):
            let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.labelColor]
            for (text, y) in [(top, rect.midY - 0.5), (bottom, rect.minY + 0.5)] where !text.isEmpty {
                (text as NSString).draw(at: NSPoint(x: x, y: y), withAttributes: attributes)
            }
        }
    }

    private static func clamp(_ value: Double) -> CGFloat { value.isFinite ? CGFloat(min(max(value, 0), 1)) : 0 }

    /// A thin rounded frame in the menu bar's text color; returns the inside.
    private static func frame(_ box: NSRect) -> NSRect {
        let path = NSBezierPath(roundedRect: box.insetBy(dx: 0.5, dy: 0.5), xRadius: 2.5, yRadius: 2.5)
        path.lineWidth = 1
        NSColor.labelColor.withAlphaComponent(0.45).setStroke()
        path.stroke()
        return box.insetBy(dx: 1.5, dy: 1.5)
    }

    /// One bar per value, newest on the right, from the middle line outward.
    private static func bars(_ values: [Double], in box: NSRect, color: NSColor, upward: Bool) {
        color.setFill()
        let slot = box.width / CGFloat(barCount)
        let shown = values.suffix(barCount)
        let offset = CGFloat(barCount - shown.count) * slot
        for (index, value) in shown.enumerated() {
            let height = box.height * clamp(value)
            guard height > 0.2 else { continue }
            NSRect(x: box.minX + offset + CGFloat(index) * slot, y: upward ? box.minY : box.maxY - height, width: slot, height: height).fill()
        }
    }
}

/// The app's mark as the menu bar shows it. Its name is AppIdentity.name.
enum AppBrand {

    /// The mark, sized for the menu bar.
    static let menuBarMark: NSImage? = {
        guard let mark = NSImage(named: "AppMark") else { return NSImage(systemSymbolName: "command", accessibilityDescription: AppIdentity.name) }
        let height: CGFloat = 13
        let image = NSImage(size: NSSize(width: (height * mark.size.width / max(mark.size.height, 1)).rounded(), height: height), flipped: false) { rect in
            mark.draw(in: rect)
            return true
        }
        return image
    }()
}
