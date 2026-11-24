import Foundation

/// One process's share of something, read from `top`.
public struct ProcessSample: Equatable, Sendable {
    public let pid: Int32
    public let command: String
    public let cpu: Double
    public let memory: UInt64
    /// Activity Monitor's "energy impact": a relative number, not watts.
    public let energy: Double

    public init(pid: Int32, command: String, cpu: Double, memory: UInt64, energy: Double) {
        self.pid = pid
        self.command = command
        self.cpu = cpu
        self.memory = memory
        self.energy = energy
    }
}

/// Reads `top -l 0 -stats pid,cpu,mem,power,command` as it streams.
///
/// `top` prints a block per interval: a few summary lines, a column header that starts with
/// "PID", then one row per process. The first block's CPU numbers are zero (top needs two looks
/// to measure), so a caller drops it.
public struct TopStreamParser {
    private var rows: [ProcessSample] = []
    private var inTable = false

    public init() {}

    /// Feeds one line. Returns the finished block when this line starts the next one.
    public mutating func feed(_ line: String) -> [ProcessSample]? {
        if line.hasPrefix("Processes:") {
            let finished = inTable ? rows : nil
            rows = []
            inTable = false
            return finished
        }
        if line.hasPrefix("PID") {
            inTable = true
            return nil
        }
        if inTable, let row = Self.row(line) { rows.append(row) }
        return nil
    }

    static func row(_ line: String) -> ProcessSample? {
        let parts = line.split(separator: " ", maxSplits: 4, omittingEmptySubsequences: true)
        // A process may name itself anything, newlines and "inf" included: only plain numbers make a row.
        guard parts.count == 5, let pid = Int32(parts[0]), let cpu = Double(parts[1]), let energy = Double(parts[3]),
              cpu.isFinite, cpu >= 0, energy.isFinite, energy >= 0 else { return nil }
        return ProcessSample(pid: pid, command: String(parts[4]).trimmingCharacters(in: .whitespaces), cpu: cpu,
                             memory: memory(String(parts[2])) ?? 0, energy: energy)
    }

    /// "2105M+", "512K", "1.2G", "10M-" → bytes. top counts in 1024s.
    public static func memory(_ text: String) -> UInt64? {
        var value = text
        while let last = value.last, last == "+" || last == "-" { value.removeLast() }
        guard let unit = value.last else { return nil }
        let multipliers: [Character: Double] = ["B": 1, "K": 1_024, "M": 1_048_576, "G": 1_073_741_824, "T": 1_099_511_627_776]
        if let multiplier = multipliers[unit], let number = Double(value.dropLast()) {
            let bytes = number * multiplier
            return bytes.isFinite && bytes >= 0 && bytes < Double(UInt64.max) ? UInt64(bytes) : nil
        }
        return UInt64(value)
    }
}

/// Reads `nettop -P -L 0 -x -J bytes_in,bytes_out` as it streams: a header line per interval,
/// then "name.pid,in,out," per process with byte counts since the process started.
public struct NettopStreamParser {
    private var rows: [Int32: (name: String, received: UInt64, sent: UInt64)] = [:]
    private var started = false

    public init() {}

    public mutating func feed(_ line: String) -> [Int32: (name: String, received: UInt64, sent: UInt64)]? {
        if line.hasPrefix(",") {
            let finished = started ? rows : nil
            rows = [:]
            started = true
            return finished
        }
        let fields = line.split(separator: ",", omittingEmptySubsequences: false)
        guard fields.count >= 3, let received = UInt64(fields[1]), let sent = UInt64(fields[2]),
              let dot = fields[0].lastIndex(of: "."), let pid = Int32(fields[0][fields[0].index(after: dot)...]) else { return nil }
        rows[pid] = (String(fields[0][..<dot]), received, sent)
        return nil
    }
}

/// Which app a process belongs to, so that Chrome's dozens of helpers count as Chrome.
public enum AppGrouping {
    /// The outermost app bundle in an executable's path, or nil for a process that is not part of an app.
    ///   "/Applications/Google Chrome.app/Contents/Frameworks/…/Helper (Renderer).app/Contents/MacOS/…"
    ///   → "/Applications/Google Chrome.app"
    public static func appBundle(forExecutable path: String) -> String? {
        guard let range = path.range(of: ".app/") else { return nil }
        return String(path[..<range.lowerBound]) + ".app"
    }
}

/// A process or an app with its helpers, ranked by one number.
public struct UsageEntry: Equatable, Sendable, Identifiable {
    /// The app bundle path, or "pid:<n>" for a lone process.
    public let id: String
    public let name: String
    /// The app bundle or executable path, for the icon; nil when unknown.
    public let path: String?
    public let value: Double

    public init(id: String, name: String, path: String?, value: Double) {
        self.id = id
        self.name = name
        self.path = path
        self.value = value
    }
}

public enum UsageRanking {
    /// Adds each process's value to its app (or keeps it alone), and returns the largest `limit`.
    /// `identity` says which app a process belongs to and what to call it.
    public static func top(_ values: [(pid: Int32, value: Double)], limit: Int,
                           identity: (Int32) -> (id: String, name: String, path: String?)) -> [UsageEntry] {
        var totals: [String: (name: String, path: String?, value: Double)] = [:]
        for item in values where item.value > 0 {
            let who = identity(item.pid)
            totals[who.id, default: (who.name, who.path, 0)].value += item.value
        }
        return totals.map { UsageEntry(id: $0.key, name: $0.value.name, path: $0.value.path, value: $0.value.value) }
            .sorted { $0.value != $1.value ? $0.value > $1.value : $0.name < $1.name }
            .prefix(limit)
            .map { $0 }
    }
}
