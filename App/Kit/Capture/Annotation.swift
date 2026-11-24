import CoreGraphics
import Foundation

/// What can be drawn on a capture.
public enum AnnotationTool: String, CaseIterable, Sendable {
    /// Pick, move and delete what is already drawn.
    case select, arrow, rectangle, pen, text, highlight, mosaic

    public var title: String {
        switch self {
        case .select: return "고르기"
        case .arrow: return "화살표"
        case .rectangle: return "상자"
        case .pen: return "펜"
        case .text: return "글자"
        case .highlight: return "형광펜"
        case .mosaic: return "모자이크"
        }
    }

    public var symbol: String {
        switch self {
        case .select: return "cursorarrow"
        case .arrow: return "arrow.up.right"
        case .rectangle: return "rectangle"
        case .pen: return "pencil.tip"
        case .text: return "textformat"
        case .highlight: return "highlighter"
        case .mosaic: return "checkerboard.rectangle"
        }
    }

    /// The key that picks the tool.
    public var key: Character {
        switch self {
        case .select: return "v"
        case .arrow: return "a"
        case .rectangle: return "r"
        case .pen: return "p"
        case .text: return "t"
        case .highlight: return "h"
        case .mosaic: return "m"
        }
    }

    /// Drawn by following the hand, point by point, rather than from one corner to another.
    public var isFreehand: Bool { self == .pen || self == .highlight }

    public init?(key: Character) {
        guard let tool = Self.allCases.first(where: { String($0.key) == String(key).lowercased() }) else { return nil }
        self = tool
    }
}

public enum AnnotationColor: String, CaseIterable, Sendable {
    case red, yellow, green, blue, white, black

    public var rgb: RGBColor {
        switch self {
        case .red: return RGBColor(red: 255, green: 69, blue: 58)
        case .yellow: return RGBColor(red: 255, green: 214, blue: 10)
        case .green: return RGBColor(red: 50, green: 215, blue: 75)
        case .blue: return RGBColor(red: 10, green: 132, blue: 255)
        case .white: return RGBColor(red: 255, green: 255, blue: 255)
        case .black: return RGBColor(red: 0, green: 0, blue: 0)
        }
    }
}

/// One thing drawn on a capture. Points are in the picture's own space: origin top-left, in points.
public struct Annotation: Identifiable, Equatable {
    public let id: UUID
    public var tool: AnnotationTool
    public var start: CGPoint
    public var end: CGPoint
    public var color: AnnotationColor
    public var lineWidth: CGFloat
    /// The words, for the text tool.
    public var text: String
    public var fontSize: CGFloat
    /// The points the hand passed through, for freehand tools. Empty for the others.
    public var points: [CGPoint]

    public init(id: UUID = UUID(), tool: AnnotationTool, start: CGPoint, end: CGPoint, color: AnnotationColor, lineWidth: CGFloat, text: String, fontSize: CGFloat,
                points: [CGPoint] = []) {
        self.id = id
        self.tool = tool
        self.start = start
        self.end = end
        self.color = color
        self.lineWidth = lineWidth
        self.text = text
        self.fontSize = fontSize
        self.points = points
    }

    /// The line a freehand stroke follows (its two ends when no points were recorded).
    public var path: [CGPoint] { points.isEmpty ? [start, end] : points }

    /// The rectangle between the two points, whichever way the drag went. For a freehand stroke,
    /// the box around all of it.
    public var rect: CGRect {
        if tool.isFreehand, let first = path.first {
            var low = first, high = first
            for point in path {
                low = CGPoint(x: min(low.x, point.x), y: min(low.y, point.y))
                high = CGPoint(x: max(high.x, point.x), y: max(high.y, point.y))
            }
            return CGRect(x: low.x, y: low.y, width: high.x - low.x, height: high.y - low.y)
        }
        return CGRect(x: min(start.x, end.x), y: min(start.y, end.y), width: abs(end.x - start.x), height: abs(end.y - start.y))
    }

    /// False for a slip of the mouse: a drag of a point or two, or text with no words.
    public var isMeaningful: Bool {
        if tool == .text { return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        return max(rect.width, rect.height) >= 4
    }

    /// Whether a click at `point` lands on this annotation.
    public func contains(_ point: CGPoint) -> Bool {
        switch tool {
        case .arrow:
            return Self.distance(from: point, toSegment: start, end) <= max(8, lineWidth)
        case .pen, .highlight:
            let line = path
            let reach = max(8, tool == .highlight ? lineWidth * 2 : lineWidth)
            return zip(line, line.dropFirst()).contains { Self.distance(from: point, toSegment: $0, $1) <= reach }
        default:
            return rect.insetBy(dx: -4, dy: -4).contains(point)
        }
    }

    static func distance(from point: CGPoint, toSegment a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = b.x - a.x, dy = b.y - a.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0 else { return hypot(point.x - a.x, point.y - a.y) }
        let t = min(max(((point.x - a.x) * dx + (point.y - a.y) * dy) / lengthSquared, 0), 1)
        return hypot(point.x - (a.x + t * dx), point.y - (a.y + t * dy))
    }
}

/// Everything drawn on one capture, with undo.
public struct AnnotationDocument: Equatable {
    public private(set) var items: [Annotation] = []
    private var undoStack: [[Annotation]] = []
    private var redoStack: [[Annotation]] = []

    public init() {}

    public var canUndo: Bool { !undoStack.isEmpty }
    public var canRedo: Bool { !redoStack.isEmpty }

    private mutating func change(_ edit: (inout [Annotation]) -> Void) {
        var next = items
        edit(&next)
        guard next != items else { return }
        undoStack.append(items)
        redoStack = []
        items = next
    }

    public mutating func add(_ annotation: Annotation) {
        change { $0.append(annotation) }
    }

    public mutating func remove(_ id: UUID) {
        change { $0.removeAll { $0.id == id } }
    }

    public mutating func move(_ id: UUID, by offset: CGSize) {
        change { items in
            guard let index = items.firstIndex(where: { $0.id == id }) else { return }
            items[index].start.x += offset.width; items[index].start.y += offset.height
            items[index].end.x += offset.width; items[index].end.y += offset.height
            items[index].points = items[index].points.map { CGPoint(x: $0.x + offset.width, y: $0.y + offset.height) }
        }
    }

    public mutating func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(items)
        items = previous
    }

    public mutating func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(items)
        items = next
    }

    /// The annotation drawn last (so on top) under `point`.
    public func hitTest(_ point: CGPoint) -> UUID? {
        items.last { $0.contains(point) }?.id
    }
}

public enum ArrowGeometry {
    /// Long enough to read as an arrow even on a thin line.
    public static func headLength(lineWidth: CGFloat) -> CGFloat { max(12, lineWidth * 4) }

    /// The triangle at the end of an arrow.
    public static func head(from: CGPoint, to: CGPoint, lineWidth: CGFloat) -> (tip: CGPoint, left: CGPoint, right: CGPoint) {
        let dx = to.x - from.x, dy = to.y - from.y
        let length = hypot(dx, dy)
        guard length > 0 else { return (to, to, to) }
        let ux = dx / length, uy = dy / length
        let size = headLength(lineWidth: lineWidth)
        let base = CGPoint(x: to.x - ux * size, y: to.y - uy * size)
        let half = size / 2
        // "Left" and "right" as seen looking from the tail to the tip, with y growing downward.
        return (to, CGPoint(x: base.x + uy * half, y: base.y - ux * half), CGPoint(x: base.x - uy * half, y: base.y + ux * half))
    }
}
