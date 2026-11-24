import Foundation
import SQLite3

public struct AppUsage: Equatable, Identifiable, Sendable {
    public let bundleID: String
    public let name: String
    public let seconds: Double
    public var id: String { bundleID }

    public init(bundleID: String, name: String, seconds: Double) {
        self.bundleID = bundleID
        self.name = name
        self.seconds = seconds
    }
}

/// Whether a moment counts as time spent at the Mac.
public enum ActivityRule {
    /// No key or mouse for this long means the user stepped away.
    public static let idleLimit: Double = 300

    /// A call (`inCall`) keeps counting past the idle limit: the user is watching and listening
    /// without touching anything. It is asked only then, and never with the display asleep.
    public static func shouldCount(idleSeconds: Double, screenLocked: Bool, displayAsleep: Bool,
                                   inCall: @autoclosure () -> Bool, enabled: Bool) -> Bool {
        guard enabled, !screenLocked, !displayAsleep else { return false }
        return idleSeconds <= idleLimit || inCall()
    }
}

public enum DurationText {
    /// "3 hr, 12 min", "45 min", "Less than 1 min"
    public static func text(_ seconds: Double, locale: Locale = .app) -> String {
        let minutes = seconds.isFinite ? Int(min(max(seconds, 0), 1e12)) / 60 : 0
        if minutes < 1 { return localized("Less than 1 min", locale: locale) }
        return units(minutes: minutes, allowed: [.hours, .minutes], locale: locale)
    }

    /// "2 PM"
    public static func hour(_ hour: Int, locale: Locale = .app) -> String {
        var style = Date.FormatStyle(date: .omitted, time: .omitted, locale: locale, timeZone: TimeZone(identifier: "UTC")!).hour()
        style.calendar = Calendar(identifier: .gregorian)
        return Date(timeIntervalSinceReferenceDate: Double(hour) * 3_600).formatted(style)
    }

    /// Whole minutes in the largest of `allowed` units, at most two of them ("6 days, 3 hr").
    static func units(minutes: Int, allowed: Set<Duration.UnitsFormatStyle.Unit>, locale: Locale) -> String {
        Duration.seconds(minutes * 60).formatted(Duration.UnitsFormatStyle(allowedUnits: allowed, width: .abbreviated, maximumUnitCount: 2).locale(locale))
    }
}

/// How long each app was in front, per day and hour. One SQLite file on this Mac, sent nowhere.
/// Use from one thread (the main thread).
public final class ScreenTimeStore {
    public enum StoreError: Error { case open(String) }

    private var db: OpaquePointer?
    private let calendar: Calendar
    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    public init(directory: URL, calendar: Calendar = .current) throws {
        self.calendar = calendar
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard sqlite3_open_v2(directory.appendingPathComponent("screentime.sqlite").path, &db,
                              SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else {
            throw StoreError.open(String(cString: sqlite3_errmsg(db)))
        }
        sqlite3_exec(db, "PRAGMA journal_mode = WAL", nil, nil, nil)
        let created = sqlite3_exec(db, """
            CREATE TABLE IF NOT EXISTS usage(
                day TEXT NOT NULL, hour INTEGER NOT NULL, bundle_id TEXT NOT NULL, name TEXT NOT NULL, seconds REAL NOT NULL,
                PRIMARY KEY(day, hour, bundle_id))
            """, nil, nil, nil)
        guard created == SQLITE_OK else { throw StoreError.open(String(cString: sqlite3_errmsg(db))) }
    }

    deinit { sqlite3_close(db) }

    /// "2026-11-13" in the user's calendar: a day is the user's day, not UTC's.
    func dayKey(_ date: Date) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// Adds time an app spent in front, to the hour `date` falls in.
    public func add(seconds: Double, bundleID: String, name: String, at date: Date) {
        guard seconds > 0 else { return }
        run("""
            INSERT INTO usage(day, hour, bundle_id, name, seconds) VALUES(?, ?, ?, ?, ?)
            ON CONFLICT(day, hour, bundle_id) DO UPDATE SET seconds = seconds + excluded.seconds, name = excluded.name
            """, [dayKey(date), calendar.component(.hour, from: date), bundleID, name, seconds])
    }

    /// The apps used on the day of `date`, longest first.
    public func apps(on date: Date) -> [AppUsage] {
        var result: [AppUsage] = []
        query("SELECT bundle_id, MAX(name), SUM(seconds) FROM usage WHERE day = ? GROUP BY bundle_id ORDER BY SUM(seconds) DESC, bundle_id", [dayKey(date)]) { row in
            result.append(AppUsage(bundleID: String(cString: sqlite3_column_text(row, 0)), name: String(cString: sqlite3_column_text(row, 1)),
                                   seconds: sqlite3_column_double(row, 2)))
        }
        return result
    }

    public func total(on date: Date) -> Double {
        var total = 0.0
        query("SELECT COALESCE(SUM(seconds), 0) FROM usage WHERE day = ?", [dayKey(date)]) { total = sqlite3_column_double($0, 0) }
        return total
    }

    /// Seconds used in each of the day's 24 hours.
    public func hourly(on date: Date) -> [Double] {
        var hours = [Double](repeating: 0, count: 24)
        query("SELECT hour, SUM(seconds) FROM usage WHERE day = ? GROUP BY hour", [dayKey(date)]) { row in
            let hour = Int(sqlite3_column_int(row, 0))
            if hours.indices.contains(hour) { hours[hour] = sqlite3_column_double(row, 1) }
        }
        return hours
    }

    /// Totals of the `days` days ending on the day of `date`, oldest first. Days without use are 0.
    public func dailyTotals(endingOn date: Date, days: Int) -> [Double] {
        (0..<max(0, days)).reversed().map { back in
            total(on: calendar.date(byAdding: .day, value: -back, to: date) ?? date)
        }
    }

    /// Like `dailyTotals` for the days before `date`, but each day counted only up to `date`'s
    /// time of day, so a morning is compared with mornings rather than with whole days.
    public func totalsByThisTime(before date: Date, days: Int) -> [Double] {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        let hour = parts.hour ?? 0, share = Double(parts.minute ?? 0) / 60
        return (1...max(1, days)).reversed().map { back in
            let hours = hourly(on: calendar.date(byAdding: .day, value: -back, to: date) ?? date)
            return hours.prefix(hour).reduce(0, +) + (hours.indices.contains(hour) ? hours[hour] * share : 0)
        }
    }

    public func clearAll() { run("DELETE FROM usage", []) }

    /// How long usage is kept.
    public static let retentionDays = 90

    /// Removes days older than `retentionDays` before `date`.
    public func prune(now date: Date) {
        guard let cutoff = calendar.date(byAdding: .day, value: -Self.retentionDays, to: date) else { return }
        run("DELETE FROM usage WHERE day < ?", [dayKey(cutoff)])
    }

    /// Adds many readings in one write (the tracker collects them for a minute).
    public func add(_ readings: [(seconds: Double, bundleID: String, name: String, date: Date)]) {
        guard !readings.isEmpty else { return }
        sqlite3_exec(db, "BEGIN", nil, nil, nil)
        for reading in readings { add(seconds: reading.seconds, bundleID: reading.bundleID, name: reading.name, at: reading.date) }
        sqlite3_exec(db, "COMMIT", nil, nil, nil)
    }

    private func bind(_ sql: String, _ values: [Any]) -> OpaquePointer? {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return nil }
        for (index, value) in values.enumerated() {
            let position = Int32(index + 1)
            switch value {
            case let value as String: sqlite3_bind_text(statement, position, value, -1, Self.transient)
            case let value as Int: sqlite3_bind_int64(statement, position, Int64(value))
            case let value as Double: sqlite3_bind_double(statement, position, value)
            default: sqlite3_bind_null(statement, position)
            }
        }
        return statement
    }

    private func run(_ sql: String, _ values: [Any]) {
        let statement = bind(sql, values)
        sqlite3_step(statement)
        sqlite3_finalize(statement)
    }

    private func query(_ sql: String, _ values: [Any], _ each: (OpaquePointer) -> Void) {
        guard let statement = bind(sql, values) else { return }
        while sqlite3_step(statement) == SQLITE_ROW { each(statement) }
        sqlite3_finalize(statement)
    }
}

/// A few plain sentences about a day's use.
public enum ScreenTimeInsights {
    /// `previousDays` are the totals of the days before, oldest first (the last one is yesterday).
    /// With `byThisTime` they are those days' use up to the present time of day, and the lines say so.
    public static func lines(apps: [AppUsage], hourly: [Double], previousDays: [Double], byThisTime: Bool = false, locale: Locale = .app) -> [String] {
        let today = apps.reduce(0) { $0 + $1.seconds }
        guard today > 0 else { return [localized("Nothing recorded yet.", locale: locale)] }
        var lines: [String] = []
        let duration = { (seconds: Double) in DurationText.text(seconds, locale: locale) }

        if let yesterday = previousDays.last, yesterday > 0 {
            let difference = today - yesterday, amount = duration(abs(difference))
            switch (byThisTime, Comparison(difference)) {
            case (false, .same): lines.append(localized("About the same as yesterday.", locale: locale))
            case (false, .more): lines.append(localized("\(amount) more than yesterday.", locale: locale))
            case (false, .less): lines.append(localized("\(amount) less than yesterday.", locale: locale))
            case (true, .same): lines.append(localized("About the same as yesterday by this time.", locale: locale))
            case (true, .more): lines.append(localized("\(amount) more than yesterday by this time.", locale: locale))
            case (true, .less): lines.append(localized("\(amount) less than yesterday by this time.", locale: locale))
            }
        }
        let used = previousDays.filter { $0 > 0 }
        if used.count >= 2 {
            let average = used.reduce(0, +) / Double(used.count)
            let difference = today - average, amount = duration(abs(difference)), mean = duration(average)
            switch (byThisTime, Comparison(difference)) {
            case (false, .same): lines.append(localized("About the same as your recent average (\(mean)).", locale: locale))
            case (false, .more): lines.append(localized("\(amount) more than your recent average (\(mean)).", locale: locale))
            case (false, .less): lines.append(localized("\(amount) less than your recent average (\(mean)).", locale: locale))
            case (true, .same): lines.append(localized("About the same as your recent average by this time (\(mean)).", locale: locale))
            case (true, .more): lines.append(localized("\(amount) more than your recent average by this time (\(mean)).", locale: locale))
            case (true, .less): lines.append(localized("\(amount) less than your recent average by this time (\(mean)).", locale: locale))
            }
        }
        if let top = apps.max(by: { $0.seconds < $1.seconds }) {
            let share = (top.seconds / today).formatted(.percent.precision(.fractionLength(0)).locale(locale))
            lines.append(localized("You used \(top.name) the most (\(duration(top.seconds)), \(share)).", locale: locale))
        }
        if let peak = hourly.indices.max(by: { hourly[$0] < hourly[$1] }), hourly[peak] > 0 {
            lines.append(localized("Your busiest hour was \(DurationText.hour(peak, locale: locale)).", locale: locale))
        }
        if let first = hourly.firstIndex(where: { $0 > 0 }), first > 0 {
            lines.append(localized("You started at \(DurationText.hour(first, locale: locale)).", locale: locale))
        }
        return lines
    }

    /// Today against another day: within a minute counts as the same.
    private enum Comparison {
        case same, more, less
        init(_ difference: Double) { self = abs(difference) < 60 ? .same : difference > 0 ? .more : .less }
    }
}
