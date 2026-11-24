import CoreGraphics
import Foundation

/// Rectangles for screen capture and measuring.
public enum CaptureGeometry {
    /// The rectangle a drag from `start` to `end` covers, whichever way it went, in whole points.
    public static func rect(from start: CGPoint, to end: CGPoint) -> CGRect {
        let x = min(start.x, end.x).rounded(), y = min(start.y, end.y).rounded()
        return CGRect(x: x, y: y, width: abs(end.x - start.x).rounded(), height: abs(end.y - start.y).rounded())
    }

    /// Converts a rectangle from AppKit's space (origin at the bottom-left of the primary display,
    /// y upward) to the capture space (origin at its top-left, y downward).
    public static func topLeftOrigin(_ rect: CGRect, primaryHeight: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    public static func sizeLabel(_ size: CGSize) -> String {
        "\(Int(size.width.rounded())) × \(Int(size.height.rounded()))"
    }

    /// A drag this small was a click or a slip, not a selection.
    public static func isUsable(_ rect: CGRect) -> Bool {
        rect.width >= 4 && rect.height >= 4
    }
}

public enum CaptureFileName {
    /// "<app name> 2027-01-15 17.00.00.png"
    public static func name(date: Date, ext: String, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        return "\(AppIdentity.name) \(formatter.string(from: date)).\(ext)"
    }

    /// `name` in `directory`, or "name 2", "name 3"… when that is taken. Nothing is ever overwritten.
    public static func uniqueURL(in directory: URL, name: String) -> URL {
        let base = (name as NSString).deletingPathExtension, ext = (name as NSString).pathExtension
        var candidate = directory.appendingPathComponent(name)
        var counter = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent(ext.isEmpty ? "\(base) \(counter)" : "\(base) \(counter).\(ext)")
            counter += 1
        }
        return candidate
    }
}

/// A color as 8-bit sRGB components.
public struct RGBColor: Equatable, Sendable {
    public let red: Int, green: Int, blue: Int

    public init(red: Int, green: Int, blue: Int) {
        self.red = min(max(red, 0), 255)
        self.green = min(max(green, 0), 255)
        self.blue = min(max(blue, 0), 255)
    }

    /// From components in 0…1 (out-of-range values are clamped).
    public init(unitRed: Double, green: Double, blue: Double) {
        self.init(red: Int((unitRed * 255).rounded()), green: Int((green * 255).rounded()), blue: Int((blue * 255).rounded()))
    }
}

/// How a picked color is written to the clipboard.
public enum ColorFormat: String, Codable, CaseIterable, Sendable {
    case hex, rgb, hsl

    public var title: String {
        switch self {
        case .hex: return "HEX"
        case .rgb: return "RGB"
        case .hsl: return "HSL"
        }
    }

    public func text(_ color: RGBColor) -> String {
        switch self {
        case .hex:
            return String(format: "#%02X%02X%02X", color.red, color.green, color.blue)
        case .rgb:
            return "rgb(\(color.red), \(color.green), \(color.blue))"
        case .hsl:
            let r = Double(color.red) / 255, g = Double(color.green) / 255, b = Double(color.blue) / 255
            let high = max(r, g, b), low = min(r, g, b), delta = high - low
            let lightness = (high + low) / 2
            var hue = 0.0, saturation = 0.0
            if delta > 0 {
                saturation = delta / (1 - abs(2 * lightness - 1))
                if high == r { hue = ((g - b) / delta).truncatingRemainder(dividingBy: 6) }
                else if high == g { hue = (b - r) / delta + 2 }
                else { hue = (r - g) / delta + 4 }
                hue *= 60
                if hue < 0 { hue += 360 }
            }
            return "hsl(\(Int(hue.rounded())), \(Int((saturation * 100).rounded()))%, \(Int((lightness * 100).rounded()))%)"
        }
    }
}
