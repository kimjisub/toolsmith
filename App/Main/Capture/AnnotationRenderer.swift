import AppKit
import ToolsmithKit

/// Draws a capture with its annotations. The same code paints the editor and the exported picture,
/// so what is saved is what was seen.
enum AnnotationRenderer {
    /// Size of one mosaic block, in points.
    static let mosaicBlock: CGFloat = 12

    /// Draws into a context whose origin is the picture's top-left, one unit per point.
    /// `size` is the picture's size in points.
    static func draw(base: CGImage, size: CGSize, items: [Annotation], selected: UUID?, in context: CGContext) {
        drawImage(base, in: CGRect(origin: .zero, size: size), context: context, smooth: true)
        for item in items {
            draw(item, base: base, size: size, in: context)
        }
        if let selected, let item = items.first(where: { $0.id == selected }) {
            context.saveGState()
            context.setStrokeColor(NSColor.white.cgColor)
            context.setLineWidth(1)
            context.setLineDash(phase: 0, lengths: [4, 3])
            context.setShadow(offset: .zero, blur: 2, color: NSColor.black.withAlphaComponent(0.8).cgColor)
            context.stroke(bounds(of: item).insetBy(dx: -5, dy: -5))
            context.restoreGState()
        }
    }

    /// The area an annotation covers, for the selection outline.
    static func bounds(of item: Annotation) -> CGRect {
        if item.tool == .text {
            let textSize = attributed(item).size()
            return CGRect(origin: item.start, size: textSize)
        }
        return item.rect
    }

    static func draw(_ item: Annotation, base: CGImage, size: CGSize, in context: CGContext) {
        let color = nsColor(item.color)
        context.saveGState()
        defer { context.restoreGState() }
        switch item.tool {
        case .select:
            break
        case .rectangle:
            context.setStrokeColor(color.cgColor)
            context.setLineWidth(item.lineWidth)
            context.setLineJoin(.round)
            context.addPath(CGPath(roundedRect: item.rect, cornerWidth: min(3, item.rect.width / 2), cornerHeight: min(3, item.rect.height / 2), transform: nil))
            context.strokePath()
        case .arrow:
            let head = ArrowGeometry.head(from: item.start, to: item.end, lineWidth: item.lineWidth)
            let base = CGPoint(x: (head.left.x + head.right.x) / 2, y: (head.left.y + head.right.y) / 2)
            context.setStrokeColor(color.cgColor)
            context.setFillColor(color.cgColor)
            context.setLineWidth(item.lineWidth)
            context.setLineCap(.round)
            context.move(to: item.start)
            context.addLine(to: base)
            context.strokePath()
            context.move(to: head.tip)
            context.addLine(to: head.left)
            context.addLine(to: head.right)
            context.closePath()
            context.fillPath()
        case .pen:
            context.setStrokeColor(color.cgColor)
            context.setLineWidth(item.lineWidth)
            context.setLineCap(.round)
            context.setLineJoin(.round)
            addPath(item.path, to: context)
            context.strokePath()
        case .highlight:
            // A wide, see-through stroke along the hand's path. Multiply keeps the text underneath
            // readable, like a real highlighter. One transparency layer, so a stroke that crosses
            // itself does not get darker where it overlaps.
            context.setBlendMode(.multiply)
            context.setAlpha(0.45)
            context.beginTransparencyLayer(auxiliaryInfo: nil)
            context.setStrokeColor(color.cgColor)
            context.setLineWidth(item.lineWidth * 4)
            context.setLineCap(.butt)
            context.setLineJoin(.round)
            addPath(item.path, to: context)
            context.strokePath()
            context.endTransparencyLayer()
        case .mosaic:
            drawMosaic(item.rect.intersection(CGRect(origin: .zero, size: size)), base: base, size: size, in: context)
        case .text:
            let graphics = NSGraphicsContext(cgContext: context, flipped: true)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = graphics
            attributed(item).draw(at: item.start)
            NSGraphicsContext.restoreGraphicsState()
        }
    }

    /// The hand's path, smoothed: straight lines between midpoints, with the recorded points as
    /// the curve's control points, so a quick stroke does not look like a row of corners.
    private static func addPath(_ points: [CGPoint], to context: CGContext) {
        guard let first = points.first else { return }
        context.move(to: first)
        guard points.count > 2 else {
            if let last = points.last { context.addLine(to: last) }
            return
        }
        for index in 1..<(points.count - 1) {
            let current = points[index], next = points[index + 1]
            context.addQuadCurve(to: CGPoint(x: (current.x + next.x) / 2, y: (current.y + next.y) / 2), control: current)
        }
        context.addLine(to: points[points.count - 1])
    }

    static func attributed(_ item: Annotation) -> NSAttributedString {
        let shadow = NSShadow()
        shadow.shadowColor = (item.color == .black ? NSColor.white : NSColor.black).withAlphaComponent(0.55)
        shadow.shadowBlurRadius = 2
        shadow.shadowOffset = .zero
        return NSAttributedString(string: item.text, attributes: [
            .font: NSFont.systemFont(ofSize: item.fontSize, weight: .semibold),
            .foregroundColor: nsColor(item.color),
            .shadow: shadow,
        ])
    }

    static func nsColor(_ color: AnnotationColor) -> NSColor {
        let rgb = color.rgb
        return NSColor(srgbRed: CGFloat(rgb.red) / 255, green: CGFloat(rgb.green) / 255, blue: CGFloat(rgb.blue) / 255, alpha: 1)
    }

    /// Draws an image the right way up in a top-left-origin context.
    private static func drawImage(_ image: CGImage, in rect: CGRect, context: CGContext, smooth: Bool) {
        context.saveGState()
        context.interpolationQuality = smooth ? .high : .none
        context.translateBy(x: rect.minX, y: rect.maxY)
        context.scaleBy(x: 1, y: -1)
        context.draw(image, in: CGRect(origin: .zero, size: rect.size))
        context.restoreGState()
    }

    /// Replaces an area with large blocks of its own average colors, so it cannot be read.
    private static func drawMosaic(_ rect: CGRect, base: CGImage, size: CGSize, in context: CGContext) {
        guard rect.width >= 1, rect.height >= 1, size.width > 0, size.height > 0 else { return }
        let scaleX = CGFloat(base.width) / size.width, scaleY = CGFloat(base.height) / size.height
        let pixels = CGRect(x: rect.minX * scaleX, y: rect.minY * scaleY, width: rect.width * scaleX, height: rect.height * scaleY).integral
        guard let crop = base.cropping(to: pixels) else { return }
        let columns = max(1, Int((rect.width / mosaicBlock).rounded(.up))), rows = max(1, Int((rect.height / mosaicBlock).rounded(.up)))
        guard let small = CGContext(data: nil, width: columns, height: rows, bitsPerComponent: 8, bytesPerRow: 0,
                                    space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
        small.interpolationQuality = .medium
        small.draw(crop, in: CGRect(x: 0, y: 0, width: columns, height: rows))
        guard let blocks = small.makeImage() else { return }
        drawImage(blocks, in: rect, context: context, smooth: false)
    }

    /// The capture with its annotations burned in, at the capture's own resolution.
    static func render(_ capture: CapturedImage, items: [Annotation]) -> CapturedImage {
        let width = capture.image.width, height = capture.image.height
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return capture }
        // Top-left origin, one unit per point.
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: capture.scale, y: -capture.scale)
        draw(base: capture.image, size: capture.pointSize, items: items, selected: nil, in: context)
        guard let image = context.makeImage() else { return capture }
        return CapturedImage(image: image, scale: capture.scale)
    }
}
