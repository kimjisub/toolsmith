import Foundation

/// "14 minutes ago": how long ago something was copied.
public enum RelativeTime {
    public static func text(from date: Date, now: Date, locale: Locale = .app) -> String {
        let seconds = Int(now.timeIntervalSince(date))
        if seconds < 60 { return localized("Just now", locale: locale) }
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = locale
        formatter.unitsStyle = .full
        let days = seconds / 86_400
        var ago = DateComponents()
        if seconds < 3_600 { ago.minute = -(seconds / 60) }
        else if seconds < 86_400 { ago.hour = -(seconds / 3_600) }
        else if days < 30 { ago.day = -days }
        else if days < 365 { ago.month = -(days / 30) }
        else { ago.year = -(days / 365) }
        return formatter.localizedString(from: ago)
    }
}

/// "1.5 KB": a size a person can read, in decimal units like Finder.
public enum ByteSize {
    public static func text(_ bytes: Int, locale: Locale = .app) -> String {
        text(Double(max(0, bytes)), step: 1_000, locale: locale)
    }

    /// `value` bytes in steps of `step` (1,000 for files, 1,024 for memory), to one decimal place.
    static func text(_ value: Double, step: Double, locale: Locale) -> String {
        let units = ["B", "KB", "MB", "GB", "TB"]
        var value = value
        var unit = 0
        while value >= step, unit < units.count - 1 {
            value /= step
            unit += 1
        }
        let number = value.formatted(.number.precision(.fractionLength(0...1)).grouping(.never).locale(locale))
        return localized("\(number) \(units[unit])", locale: locale)
    }
}
