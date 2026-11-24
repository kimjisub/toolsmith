import Foundation
import SQLite3

/// What the monitor keeps a history of.
public enum Metric: Int, CaseIterable, Sendable {
    // The numbers are stored on disk: never renumber, only add.
    case cpuUser = 1, cpuSystem = 2, gpu = 3, memoryPressure = 4, memoryUsed = 5, download = 6, upload = 7, diskRead = 8, diskWrite = 9
    case systemPower = 10, batteryLevel = 11, batteryTemperature = 12, cpuTemperature = 13
}

/// How far back a history graph looks.
public enum HistoryRange: Int, CaseIterable, Identifiable, Sendable {
    case tenMinutes = 600, oneHour = 3_600, threeHours = 10_800, sixHours = 21_600, twelveHours = 43_200
    case oneDay = 86_400, threeDays = 259_200, sevenDays = 604_800, fourteenDays = 1_209_600, twentyEightDays = 2_419_200

    public var id: Int { rawValue }
    public var seconds: TimeInterval { TimeInterval(rawValue) }

    public var label: String {
        switch self {
        case .tenMinutes: return localized("10 Minutes")
        case .oneHour: return localized("1 Hour")
        case .threeHours: return localized("3 Hours")
        case .sixHours: return localized("6 Hours")
        case .twelveHours: return localized("12 Hours")
        case .oneDay: return localized("1 Day")
        case .threeDays: return localized("3 Days")
        case .sevenDays: return localized("7 Days")
        case .fourteenDays: return localized("14 Days")
        case .twentyEightDays: return localized("28 Days")
        }
    }

    /// Ranges up to this long are drawn from the recent readings in memory; longer ones from the
    /// per-minute averages on disk.
    public var usesRecentReadings: Bool { self <= .oneHour }
}

extension HistoryRange: Comparable {
    public static func < (lhs: HistoryRange, rhs: HistoryRange) -> Bool { lhs.rawValue < rhs.rawValue }
}

public struct TimedValue: Equatable, Sendable {
    public let time: TimeInterval
    public let value: Double

    public init(time: TimeInterval, value: Double) {
        self.time = time
        self.value = value
    }
}

/// The last hour of readings of each metric, in memory.
public struct RecentReadings: Sendable {
    public static let span: TimeInterval = 3_600
    private var values: [Metric: [TimedValue]] = [:]

    public init() {}

    public mutating func add(_ metric: Metric, _ value: Double, at time: TimeInterval) {
        var list = values[metric, default: []]
        list.append(TimedValue(time: time, value: value))
        if let first = list.first, time - first.time > Self.span {
            list.removeFirst(list.firstIndex { time - $0.time <= Self.span } ?? 0)
        }
        values[metric] = list
    }

    public func values(_ metric: Metric, since start: TimeInterval) -> [TimedValue] {
        (values[metric] ?? []).filter { $0.time >= start }
    }
}

public enum HistoryBuckets {
    /// Averages `points` into `count` equal slices of [start, end]. A slice with no reading is nil,
    /// so a graph shows the gap (the Mac was asleep or the app was not running).
    public static func average(_ points: [TimedValue], start: TimeInterval, end: TimeInterval, count: Int) -> [Double?] {
        guard count > 0, end > start else { return [] }
        var sums = [Double](repeating: 0, count: count), counts = [Int](repeating: 0, count: count)
        let width = (end - start) / Double(count)
        for point in points where point.time >= start && point.time <= end {
            let index = min(count - 1, Int((point.time - start) / width))
            sums[index] += point.value
            counts[index] += 1
        }
        return (0..<count).map { counts[$0] > 0 ? sums[$0] / Double(counts[$0]) : nil }
    }
}

/// Averages of each metric for the last 28 days, in one SQLite file on this Mac, sent nowhere.
/// The last 3 days keep one average per minute; older days one per 10 minutes, which is all a graph
/// of a week or more can show. That keeps the file to a few megabytes.
/// Not thread-safe: use from one queue.
public final class MetricHistoryStore: @unchecked Sendable {
    public enum StoreError: Error { case open(String) }
    public static let retention: TimeInterval = HistoryRange.twentyEightDays.seconds
    /// Minute averages older than this are folded into 10-minute averages.
    public static let fineRetention: TimeInterval = 3 * 86_400
    static let coarseMinutes: Int64 = 10

    private var db: OpaquePointer?
    /// Readings of the minute in progress, averaged and written when the minute ends.
    private var pending: [Metric: (minute: Int64, sum: Double, count: Int)] = [:]
    private var lastCompaction: TimeInterval = 0

    public init(directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard sqlite3_open_v2(directory.appendingPathComponent("history-v2.sqlite").path, &db,
                              SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else {
            throw StoreError.open(String(cString: sqlite3_errmsg(db)))
        }
        // A lost last minute after a power cut is fine; an fsync on every write is not.
        for pragma in ["PRAGMA journal_mode = WAL", "PRAGMA synchronous = NORMAL", "PRAGMA journal_size_limit = 1048576"] {
            sqlite3_exec(db, pragma, nil, nil, nil)
        }
        // `minutes` is 1 for a minute average, 10 for a 10-minute one; `start` is its first minute since 1970.
        let schema = "CREATE TABLE IF NOT EXISTS average (metric INTEGER NOT NULL, minutes INTEGER NOT NULL, start INTEGER NOT NULL, value REAL NOT NULL, PRIMARY KEY (metric, minutes, start)) WITHOUT ROWID"
        guard sqlite3_exec(db, schema, nil, nil, nil) == SQLITE_OK else { throw StoreError.open(String(cString: sqlite3_errmsg(db))) }
    }

    deinit {
        flush()
        sqlite3_close(db)
    }

    /// One reading of several metrics. Minutes that ended are written together, in one transaction.
    public func add(_ values: [(Metric, Double)], at time: TimeInterval) {
        let minute = Int64(time / 60)
        var finished: [(Metric, Int64, Double)] = []
        for (metric, value) in values where value.isFinite {
            if let current = pending[metric], current.minute != minute {
                finished.append((metric, current.minute, current.sum / Double(current.count)))
                pending[metric] = nil
            }
            var entry = pending[metric] ?? (minute, 0, 0)
            entry.sum += value
            entry.count += 1
            pending[metric] = entry
        }
        write(finished)
        if time - lastCompaction > 3_600 {
            lastCompaction = time
            compact(now: time)
        }
    }

    /// Forgets every recorded minute.
    public func removeAll() {
        pending = [:]
        sqlite3_exec(db, "DELETE FROM average", nil, nil, nil)
        sqlite3_exec(db, "PRAGMA wal_checkpoint(TRUNCATE)", nil, nil, nil)
        sqlite3_exec(db, "VACUUM", nil, nil, nil)
    }

    /// Writes the minutes in progress (before quitting).
    public func flush() {
        write(pending.map { ($0.key, $0.value.minute, $0.value.sum / Double($0.value.count)) })
        pending = [:]
    }

    /// Averages since `start`, oldest first, the minute in progress included, as (time, value).
    public func values(_ metric: Metric, since start: TimeInterval) -> [TimedValue] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT minutes, start, value FROM average WHERE metric = ? AND start >= ? ORDER BY start", -1, &statement, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int64(statement, 1, Int64(metric.rawValue))
        sqlite3_bind_int64(statement, 2, Int64(start / 60) - Self.coarseMinutes)
        var result: [TimedValue] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let minutes = Double(sqlite3_column_int64(statement, 0))
            // Each average stands at the middle of its span.
            let time = Double(sqlite3_column_int64(statement, 1)) * 60 + minutes * 30
            if time >= start { result.append(TimedValue(time: time, value: sqlite3_column_double(statement, 2))) }
        }
        if let entry = pending[metric], Double(entry.minute) * 60 >= start {
            result.append(TimedValue(time: Double(entry.minute) * 60 + 30, value: entry.sum / Double(entry.count)))
        }
        return result
    }

    /// Folds minute averages older than `fineRetention` into 10-minute ones and drops what is older than `retention`.
    public func compact(now time: TimeInterval) {
        let fineCutoff = Int64((time - Self.fineRetention) / 60) / Self.coarseMinutes * Self.coarseMinutes
        let cutoff = Int64((time - Self.retention) / 60)
        transaction {
            run("""
                INSERT OR REPLACE INTO average (metric, minutes, start, value)
                SELECT metric, ?, start / ? * ?, AVG(value) FROM average WHERE minutes = 1 AND start < ? GROUP BY metric, start / ?
                """, [Self.coarseMinutes, Self.coarseMinutes, Self.coarseMinutes, fineCutoff, Self.coarseMinutes])
            run("DELETE FROM average WHERE minutes = 1 AND start < ?", [fineCutoff])
            run("DELETE FROM average WHERE start < ?", [cutoff])
        }
    }

    private func write(_ rows: [(Metric, Int64, Double)]) {
        guard !rows.isEmpty else { return }
        transaction {
            for (metric, minute, value) in rows {
                run("INSERT OR REPLACE INTO average (metric, minutes, start, value) VALUES (?, 1, ?, ?)", [Int64(metric.rawValue), minute], value)
            }
        }
    }

    private func transaction(_ body: () -> Void) {
        sqlite3_exec(db, "BEGIN", nil, nil, nil)
        body()
        sqlite3_exec(db, "COMMIT", nil, nil, nil)
    }

    private func run(_ sql: String, _ integers: [Int64], _ real: Double? = nil) {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(statement) }
        for (index, value) in integers.enumerated() { sqlite3_bind_int64(statement, Int32(index + 1), value) }
        if let real { sqlite3_bind_double(statement, Int32(integers.count + 1), real) }
        sqlite3_step(statement)
    }
}
