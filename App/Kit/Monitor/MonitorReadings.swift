import Foundation

/// How the CPU's busy time split between apps and the system over one interval (each 0…100).
public struct CPUUsage: Equatable, Sendable {
    public var user: Double, system: Double

    public init(user: Double = 0, system: Double = 0) {
        self.user = user
        self.system = system
    }

    public var total: Double { min(100, user + system) }

    /// `nice` (lowered priority) time is app work too, so it counts as user.
    public static func between(_ before: CPUTicks, _ after: CPUTicks) -> CPUUsage {
        guard after.user >= before.user, after.system >= before.system, after.idle >= before.idle, after.nice >= before.nice else { return CPUUsage() }
        let user = Double(after.user - before.user) + Double(after.nice - before.nice)
        let system = Double(after.system - before.system)
        let total = user + system + Double(after.idle - before.idle)
        guard total > 0 else { return CPUUsage() }
        return CPUUsage(user: user / total * 100, system: system / total * 100)
    }
}

/// One group of CPU cores that run alike (performance, efficiency, super), as the kernel names them.
public struct CoreCluster: Equatable, Sendable {
    public let name: String
    public let count: Int

    public init(name: String, count: Int) {
        self.name = name
        self.count = count
    }

    /// "성능 코어", "효율 코어", "슈퍼 코어"; an unknown name stays as it is.
    public var label: String {
        switch name.lowercased() {
        case "performance": return "성능 코어"
        case "efficiency": return "효율 코어"
        case "super": return "슈퍼 코어"
        default: return name
        }
    }

    /// Which cluster each logical CPU belongs to, in the kernel's CPU order. Apple silicon numbers
    /// the slowest cores first, and `sysctl` lists perf levels fastest first, so the order flips.
    public static func assign(clusters: [CoreCluster], coreCount: Int) -> [Int] {
        guard !clusters.isEmpty, clusters.map(\.count).reduce(0, +) == coreCount else { return Array(repeating: 0, count: coreCount) }
        var result: [Int] = []
        for index in clusters.indices.reversed() {
            result += Array(repeating: index, count: clusters[index].count)
        }
        return result
    }
}

/// Where memory went, the way Activity Monitor splits it.
public struct MemoryBreakdown: Equatable, Sendable {
    public var total: UInt64 = 0
    /// Memory apps hold that the system cannot simply drop.
    public var app: UInt64 = 0
    public var wired: UInt64 = 0
    public var compressed: UInt64 = 0
    /// File contents kept around in case they are read again; given away when asked.
    public var cached: UInt64 = 0
    public var swapUsed: UInt64 = 0
    /// 0…100. How hard the system is working to find memory: 0 is relaxed, 100 is out of memory.
    public var pressure: Double = 0

    public init() {}

    public init(total: UInt64, internalPages: UInt64, purgeablePages: UInt64, externalPages: UInt64,
                wiredPages: UInt64, compressorPages: UInt64, pageSize: UInt64, swapUsed: UInt64, freeLevel: Int) {
        self.total = total
        let purgeable = min(purgeablePages, internalPages)
        app = (internalPages - purgeable) * pageSize
        wired = wiredPages * pageSize
        compressed = compressorPages * pageSize
        cached = (externalPages + purgeable) * pageSize
        self.swapUsed = swapUsed
        // The kernel reports how much is available (0…100); pressure is the rest.
        pressure = Double(min(max(100 - freeLevel, 0), 100))
    }

    public var used: UInt64 { app + wired + compressed }
    /// Everything not in use, cached files included.
    public var free: UInt64 { total > used ? total - used : 0 }
    public var usedPercent: Double { total > 0 ? min(100, Double(used) / Double(total) * 100) : 0 }

    /// The parts of the memory ring, in drawing order, as fractions of the whole.
    public var fractions: [Double] {
        guard total > 0 else { return [0, 0, 0] }
        return [app, wired, compressed].map { Double($0) / Double(total) }
    }
}

/// Bytes per second from two readings of a growing counter, per key. Keys that are new or whose
/// counter went backwards count as zero.
public enum CounterRates {
    public static func rates<Key: Hashable>(before: [Key: UInt64], after: [Key: UInt64], seconds: Double) -> [Key: Double] {
        guard seconds > 0 else { return [:] }
        var result: [Key: Double] = [:]
        for (key, value) in after {
            guard let old = before[key], value >= old else { continue }
            result[key] = Double(value - old) / seconds
        }
        return result
    }
}

/// How long the Mac has been on: "6일", "3시간 12분", "12분".
public enum UptimeText {
    public static func text(_ seconds: Double) -> String {
        let minutes = seconds.isFinite ? Int(min(max(seconds, 0), 1e12)) / 60 : 0
        let days = minutes / 1_440, hours = minutes / 60 % 24, rest = minutes % 60
        if days > 0 { return hours > 0 ? "\(days)일 \(hours)시간" : "\(days)일" }
        if hours > 0 { return rest > 0 ? "\(hours)시간 \(rest)분" : "\(hours)시간" }
        return "\(rest)분"
    }
}

/// Numbers as the monitor shows them.
public enum MonitorText {
    /// "1.2MB/초", "512KB/초"
    public static func rate(_ bytesPerSecond: Double) -> String {
        ByteSize.text(bytesPerSecond.isFinite ? Int(min(max(bytesPerSecond, 0), 1e15).rounded()) : 0) + "/초"
    }

    /// "9.3 W", "450 mW"
    public static func watts(_ watts: Double) -> String {
        guard watts.isFinite else { return "-" }
        if watts < 1 { return "\(Int((watts * 1_000).rounded())) mW" }
        return watts < 10 ? String(format: "%.1f W", watts) : String(format: "%.0f W", watts)
    }

    /// "4.16 GHz", "850 MHz"
    public static func frequency(megahertz: Double) -> String {
        guard megahertz.isFinite else { return "-" }
        return megahertz >= 1_000 ? String(format: "%.2f GHz", megahertz / 1_000) : String(format: "%.0f MHz", megahertz)
    }

    /// A reading as a whole number; "-" for a value a broken sensor or counter can produce (NaN, ∞).
    public static func whole(_ value: Double) -> String {
        guard value.isFinite, abs(value) < 1e15 else { return "-" }
        return "\(Int(value.rounded()))"
    }

    public static func percent(_ value: Double) -> String { whole(value) + "%" }

    /// Memory in the binary units macOS uses for it (a 96 GB Mac shows "96GB", not "103.1GB").
    public static func memory(_ bytes: UInt64) -> String {
        let units = ["B", "KB", "MB", "GB", "TB"]
        var value = Double(bytes), unit = 0
        while value >= 1_024, unit < units.count - 1 {
            value /= 1_024
            unit += 1
        }
        let rounded = (value * 10).rounded() / 10
        return rounded == rounded.rounded() ? "\(Int(rounded))\(units[unit])" : "\(rounded)\(units[unit])"
    }

    public static func temperature(_ celsius: Double) -> String { whole(celsius) + "°" }
}
