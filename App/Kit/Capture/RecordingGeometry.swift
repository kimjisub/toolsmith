import CoreGraphics
import Foundation

/// Numbers a screen recording needs.
public enum RecordingGeometry {
    /// The part of a display to record: `selection` and `displayFrame` are in AppKit screen
    /// coordinates (origin bottom-left, y up); the result is local to the display with its origin
    /// at the display's top-left, clipped to the display.
    public static func sourceRect(selection: CGRect, displayFrame: CGRect) -> CGRect {
        let clipped = selection.intersection(displayFrame)
        guard !clipped.isNull else { return .zero }
        return CGRect(x: clipped.minX - displayFrame.minX, y: displayFrame.maxY - clipped.maxY, width: clipped.width, height: clipped.height)
    }

    /// The video's size in pixels. Encoders need even numbers.
    public static func pixelSize(points: CGSize, scale: CGFloat) -> (width: Int, height: Int) {
        func even(_ value: CGFloat) -> Int { max(2, Int(value.rounded(.down)) / 2 * 2) }
        return (even(points.width * scale), even(points.height * scale))
    }

    /// "01:15", or "1:02:03" past an hour.
    public static func elapsedLabel(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        let hours = total / 3_600, minutes = total % 3_600 / 60, rest = total % 60
        return hours > 0 ? String(format: "%d:%02d:%02d", hours, minutes, rest) : String(format: "%02d:%02d", minutes, rest)
    }
}

/// How a recording becomes a GIF: fewer frames and a smaller picture than the video, to keep the file light.
public enum GIFPlan {
    public static let fps = 12
    public static let maxWidth = 960

    /// The moments, in seconds, to take a frame at. Always at least the first frame.
    public static func frameTimes(duration: Double, fps: Int) -> [Double] {
        let count = max(1, Int((duration * Double(fps)).rounded(.down)))
        return (0..<count).map { Double($0) / Double(fps) }
    }

    public static func size(width: Int, height: Int, maxWidth: Int) -> (width: Int, height: Int) {
        guard width > maxWidth, width > 0 else { return (width, height) }
        return (maxWidth, max(1, Int((Double(height) * Double(maxWidth) / Double(width)).rounded())))
    }
}
