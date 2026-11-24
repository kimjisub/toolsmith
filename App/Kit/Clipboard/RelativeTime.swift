import Foundation

/// "14분 전": how long ago something was copied.
public enum RelativeTime {
    public static func text(from date: Date, now: Date) -> String {
        let seconds = Int(now.timeIntervalSince(date))
        if seconds < 60 { return "방금" }
        if seconds < 3_600 { return "\(seconds / 60)분 전" }
        if seconds < 86_400 { return "\(seconds / 3_600)시간 전" }
        let days = seconds / 86_400
        if days < 30 { return "\(days)일 전" }
        if days < 365 { return "\(days / 30)개월 전" }
        return "\(days / 365)년 전"
    }
}

/// "1.5KB": a size a person can read.
public enum ByteSize {
    public static func text(_ bytes: Int) -> String {
        let units = ["B", "KB", "MB", "GB", "TB"]
        var value = Double(max(0, bytes))
        var unit = 0
        while value >= 1_000, unit < units.count - 1 {
            value /= 1_000
            unit += 1
        }
        let rounded = (value * 10).rounded() / 10
        return rounded == rounded.rounded() ? "\(Int(rounded))\(units[unit])" : "\(rounded)\(units[unit])"
    }
}
