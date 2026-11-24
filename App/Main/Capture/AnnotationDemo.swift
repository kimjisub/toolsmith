import AppKit
import ToolsmithKit

/// A made-up capture with one of each annotation, for checking the renderer by eye.
@MainActor enum AnnotationDemo {
    static func render(to url: URL) {
        let size = CGSize(width: 640, height: 360), scale: CGFloat = 2
        let image = NSImage(size: size, flipped: true) { rect in
            NSColor(white: 0.96, alpha: 1).setFill()
            rect.fill()
            let lines = ["Phone: 000-000-0000", "Are you free for a call tomorrow at 3 PM?", "I’ll send the draft minutes by Friday.", "\(AppIdentity.name) annotation demo"]
            for (index, line) in lines.enumerated() {
                NSAttributedString(string: line, attributes: [.font: NSFont.systemFont(ofSize: 20), .foregroundColor: NSColor.black])
                    .draw(at: CGPoint(x: 40, y: 50 + CGFloat(index) * 60))
            }
            return true
        }
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale), bitsPerSample: 8,
                                            samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return }
        bitmap.size = size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        image.draw(in: CGRect(origin: .zero, size: size))
        NSGraphicsContext.restoreGraphicsState()
        guard let base = bitmap.cgImage else { return }

        func make(_ tool: AnnotationTool, _ x1: CGFloat, _ y1: CGFloat, _ x2: CGFloat, _ y2: CGFloat, _ color: AnnotationColor, text: String = "") -> Annotation {
            Annotation(tool: tool, start: CGPoint(x: x1, y: y1), end: CGPoint(x: x2, y: y2), color: color, lineWidth: 5, text: text, fontSize: 22)
        }
        let items = [
            make(.mosaic, 170, 44, 330, 80, .red),
            Annotation(tool: .highlight, start: CGPoint(x: 40, y: 122), end: CGPoint(x: 400, y: 124), color: .yellow, lineWidth: 5, text: "", fontSize: 22,
                       points: [CGPoint(x: 40, y: 122), CGPoint(x: 160, y: 126), CGPoint(x: 280, y: 120), CGPoint(x: 400, y: 124)]),
            Annotation(tool: .pen, start: CGPoint(x: 60, y: 270), end: CGPoint(x: 330, y: 268), color: .green, lineWidth: 5, text: "", fontSize: 22,
                       points: stride(from: 0, through: 27, by: 1).map { CGPoint(x: 60 + CGFloat($0) * 10, y: 268 + sin(CGFloat($0) * 0.7) * 9) }),
            make(.rectangle, 30, 160, 450, 206, .red),
            make(.arrow, 560, 300, 420, 240, .blue),
            make(.text, 470, 300, 470, 300, .blue, text: "Check this"),
        ]
        let result = AnnotationRenderer.render(CapturedImage(image: base, scale: scale), items: items)
        try? result.pngData?.write(to: url)
    }
}
