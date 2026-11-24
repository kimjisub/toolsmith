import CoreGraphics
import Foundation

/// Where a window goes. Pure geometry in the accessibility coordinate space: the origin is the
/// top-left of the primary display and y grows downward.
public enum WindowLayout {
    /// The frame `action` gives a window on a screen whose usable area (without menu bar and
    /// Dock) is `visible`. `gap` is the space left between tiles and around the edges.
    /// nil for actions that need more than one screen's geometry (display moves, restore).
    public static func frame(for action: WindowAction, window: CGRect, visible: CGRect, gap: CGFloat) -> CGRect? {
        switch action {
        case .leftHalf: return tile(visible, gap, column: 0, of: 2)
        case .rightHalf: return tile(visible, gap, column: 1, of: 2)
        case .topHalf: return tile(visible, gap, row: 0, outOf: 2)
        case .bottomHalf: return tile(visible, gap, row: 1, outOf: 2)
        case .leftThird: return tile(visible, gap, column: 0, of: 3)
        case .centerThird: return tile(visible, gap, column: 1, of: 3)
        case .rightThird: return tile(visible, gap, column: 2, of: 3)
        case .leftTwoThirds: return tile(visible, gap, column: 0, span: 2, of: 3)
        case .rightTwoThirds: return tile(visible, gap, column: 1, span: 2, of: 3)
        case .topLeft: return tile(visible, gap, column: 0, of: 2, row: 0, outOf: 2)
        case .topRight: return tile(visible, gap, column: 1, of: 2, row: 0, outOf: 2)
        case .bottomLeft: return tile(visible, gap, column: 0, of: 2, row: 1, outOf: 2)
        case .bottomRight: return tile(visible, gap, column: 1, of: 2, row: 1, outOf: 2)
        case .maximize: return tile(visible, gap)
        case .center:
            // Same size, centered; a window larger than the screen is cut down to fit.
            let size = CGSize(width: min(window.width, visible.width), height: min(window.height, visible.height))
            return CGRect(x: (visible.midX - size.width / 2).rounded(), y: (visible.midY - size.height / 2).rounded(),
                          width: size.width, height: size.height)
        case .nextDisplay, .previousDisplay, .restore:
            return nil
        }
    }

    /// The same relative place and size on another screen, kept fully inside it.
    public static func moved(_ window: CGRect, from: CGRect, to: CGRect) -> CGRect {
        guard from.width > 0, from.height > 0 else { return window }
        let width = min((window.width / from.width * to.width).rounded(), to.width)
        let height = min((window.height / from.height * to.height).rounded(), to.height)
        var x = (to.minX + (window.minX - from.minX) / from.width * to.width).rounded()
        var y = (to.minY + (window.minY - from.minY) / from.height * to.height).rounded()
        x = min(max(x, to.minX), to.maxX - width)
        y = min(max(y, to.minY), to.maxY - height)
        return CGRect(x: x, y: y, width: width, height: height)
    }

    /// One cell (or a run of cells) of a grid laid over `visible`, with `gap` between cells and at the edges.
    private static func tile(_ visible: CGRect, _ gap: CGFloat, column: Int = 0, span: Int = 1, of columns: Int = 1,
                             row: Int = 0, outOf rows: Int = 1) -> CGRect {
        let cellWidth = (visible.width - gap * CGFloat(columns + 1)) / CGFloat(columns)
        let cellHeight = (visible.height - gap * CGFloat(rows + 1)) / CGFloat(rows)
        let x = visible.minX + gap + CGFloat(column) * (cellWidth + gap)
        let y = visible.minY + gap + CGFloat(row) * (cellHeight + gap)
        let width = CGFloat(span) * cellWidth + CGFloat(span - 1) * gap
        return CGRect(x: x.rounded(), y: y.rounded(), width: width.rounded(), height: cellHeight.rounded())
    }
}
