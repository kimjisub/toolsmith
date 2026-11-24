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

    /// "Performance Cores", "Efficiency Cores", "Super Cores"; an unknown name stays as it is.
    public var label: String { label(locale: .app) }

    public func label(locale: Locale) -> String {
        switch name.lowercased() {
        case "performance": return localized("Performance Cores", locale: locale)
        case "efficiency": return localized("Efficiency Cores", locale: locale)
        case "super": return localized("Super Cores", locale: locale)
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

/// How long the Mac has been on: "6 days", "3 hr, 12 min", "12 min".
public enum UptimeText {
    public static func text(_ seconds: Double, locale: Locale = .app) -> String {
        let minutes = seconds.isFinite ? Int(min(max(seconds, 0), 1e12)) / 60 : 0
        // Days and hours, or hours and minutes: never all three.
        let shown = minutes >= 1_440 ? minutes / 60 * 60 : minutes
        return DurationText.units(minutes: shown, allowed: [.days, .hours, .minutes], locale: locale)
    }
}

/// Numbers as the monitor shows them.
public enum MonitorText {
    /// "1.2 MB/s", "512 KB/s"
    public static func rate(_ bytesPerSecond: Double, locale: Locale = .app) -> String {
        let size = ByteSize.text(bytesPerSecond.isFinite ? Int(min(max(bytesPerSecond, 0), 1e15).rounded()) : 0, locale: locale)
        return localized("\(size)/s", locale: locale)
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

    /// Memory in the binary units macOS uses for it (a 96 GB Mac shows "96 GB", not "103.1 GB").
    public static func memory(_ bytes: UInt64, locale: Locale = .app) -> String {
        ByteSize.text(Double(bytes), step: 1_024, locale: locale)
    }

    public static func temperature(_ celsius: Double) -> String { whole(celsius) + "°" }
}
