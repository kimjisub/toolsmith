import Foundation

/// Joins pictures of a scrolling page into one tall picture.
///
/// Each picture is reduced to one number per pixel row. Two consecutive pictures overlap; finding
/// how far the rows moved says which rows of the newer picture are new.
public enum ScrollStitch {
    /// Rows may differ in a few places (a blinking caret, a hover effect) and still count as the same view.
    static let requiredMatch = 0.95
    /// At least this many rows must overlap for a shift to be believed.
    static let minimumOverlap = 8

    /// How many rows the content moved up between `previous` and `next` (0 when it did not move),
    /// or nil when the two do not overlap recognizably.
    ///
    /// A header that stays put while the page scrolls would make every row comparison fail at the
    /// top, so rows are compared from below the part that is identical in both pictures.
    public static func shift(previous: [UInt64], next: [UInt64]) -> Int? {
        let height = previous.count
        guard height > 0, next.count == height else { return nil }
        if matches(previous, next, shift: 0, from: 0) { return 0 }

        // Rows at the top that did not change at all: a fixed header (or nothing).
        var fixed = 0
        while fixed < height, previous[fixed] == next[fixed] { fixed += 1 }
        let start = fixed < height / 2 ? fixed : 0

        for candidate in 1..<height where matches(previous, next, shift: candidate, from: start) {
            return candidate
        }
        return nil
    }

    /// Whether `next`, from row `start`, equals `previous` moved up by `shift` rows.
    private static func matches(_ previous: [UInt64], _ next: [UInt64], shift: Int, from start: Int) -> Bool {
        let overlap = previous.count - shift - start
        guard overlap >= min(minimumOverlap, previous.count) else { return false }
        var same = 0
        for row in start..<(start + overlap) where next[row] == previous[row + shift] { same += 1 }
        return Double(same) >= Double(overlap) * requiredMatch
    }

    /// Keeps count of the tall picture as frames arrive.
    public struct Plan {
        public let frameHeight: Int
        public private(set) var totalHeight: Int

        public init(frameHeight: Int) {
            self.frameHeight = frameHeight
            totalHeight = frameHeight
        }

        /// The rows of the newest frame to add at the bottom, or nil when it brought nothing new.
        public mutating func append(shift: Int) -> Range<Int>? {
            let added = min(max(shift, 0), frameHeight)
            guard added > 0 else { return nil }
            totalHeight += added
            return (frameHeight - added)..<frameHeight
        }
    }
}
