import Foundation

/// CPU time counters since boot, as the kernel reports them.
public struct CPUTicks: Equatable, Sendable {
    public let user: UInt64, system: UInt64, idle: UInt64, nice: UInt64

    public init(user: UInt64, system: UInt64, idle: UInt64, nice: UInt64) {
        self.user = user
        self.system = system
        self.idle = idle
        self.nice = nice
    }

    /// Percent of the time between two readings that the CPU was busy (0…100).
    public static func usage(from before: CPUTicks, to after: CPUTicks) -> Double {
        guard after.user >= before.user, after.system >= before.system, after.idle >= before.idle, after.nice >= before.nice else { return 0 }
        let busy = Double(after.user - before.user) + Double(after.system - before.system) + Double(after.nice - before.nice)
        let total = busy + Double(after.idle - before.idle)
        return total > 0 ? busy / total * 100 : 0
    }
}

public enum NetworkCounters {
    /// Bytes per second between two readings of a byte counter. A counter that went backwards
    /// (an interface that restarted) counts as zero rather than a huge number.
    public static func rate(from before: UInt64, to after: UInt64, seconds: Double) -> Double {
        guard seconds > 0, after >= before else { return 0 }
        return Double(after - before) / seconds
    }
}

public extension ByteSize {
    /// "1.5KB/s"
    static func rate(_ bytesPerSecond: Double) -> String { text(Int(bytesPerSecond.rounded())) + "/s" }
}

/// The last few readings of something, for a small graph.
public struct History: Equatable, Sendable {
    public let capacity: Int
    public private(set) var values: [Double] = []

    public init(capacity: Int) { self.capacity = max(1, capacity) }

    public mutating func push(_ value: Double) {
        values.append(value)
        if values.count > capacity { values.removeFirst(values.count - capacity) }
    }

    public var peak: Double { values.max() ?? 0 }
}

/// Turns the raw bytes the System Management Controller returns into a number.
public enum SMCValue {
    public static func decode(type: String, bytes: [UInt8]) -> Double? {
        switch type {
        case "flt ":
            guard bytes.count >= 4 else { return nil }
            return Double(Float(bitPattern: UInt32(bytes[0]) | UInt32(bytes[1]) << 8 | UInt32(bytes[2]) << 16 | UInt32(bytes[3]) << 24))
        case "sp78":
            // Signed fixed point: 8 integer bits, 8 fraction bits, big-endian.
            guard bytes.count >= 2 else { return nil }
            return Double(Int16(bitPattern: UInt16(bytes[0]) << 8 | UInt16(bytes[1]))) / 256
        case "fpe2":
            // Unsigned fixed point with 2 fraction bits, big-endian (fan speeds on Intel).
            guard bytes.count >= 2 else { return nil }
            return Double(UInt16(bytes[0]) << 8 | UInt16(bytes[1])) / 4
        case "ui8 ":
            return bytes.first.map(Double.init)
        case "ui16":
            guard bytes.count >= 2 else { return nil }
            return Double(UInt16(bytes[0]) << 8 | UInt16(bytes[1]))
        case "ui32":
            guard bytes.count >= 4 else { return nil }
            return Double(UInt32(bytes[0]) << 24 | UInt32(bytes[1]) << 16 | UInt32(bytes[2]) << 8 | UInt32(bytes[3]))
        default:
            return nil
        }
    }
}

/// The temperatures worth showing, picked out of the many sensors a Mac has.
public struct TemperatureSummary: Equatable, Sendable {
    /// The average of the CPU core sensors, and the hottest of them.
    public let cpu: Double?, cpuPeak: Double?
    public let gpu: Double?, battery: Double?

    // Apple silicon performance and efficiency cores, Intel CPU.
    static let cpuPrefixes = ["Tp", "Te", "TC"]
    static let gpuPrefixes = ["Tg", "TG"]
    static let batteryPrefixes = ["TB"]

    /// Whether a sensor is one of those shown. A Mac has a couple of hundred; only these are read.
    public static func wanted(_ key: String) -> Bool {
        (cpuPrefixes + gpuPrefixes + batteryPrefixes).contains { key.hasPrefix($0) }
    }

    /// The few sensors read while the monitor is closed (the menu bar and the history need only the
    /// summary): up to 8 CPU, 2 GPU and 2 battery sensors that read a real value. Many Macs report
    /// exactly 40.0 for sensors of parts that are powered down; those say nothing.
    public static func lightKeys(_ readings: [String: Double]) -> [String] {
        let live = readings.filter { $0.value > 1 && $0.value < 130 && $0.value != 40 }.keys.sorted()
        func pick(_ prefixes: [String], _ count: Int) -> [String] {
            Array(live.filter { key in prefixes.contains { key.hasPrefix($0) } }.prefix(count))
        }
        return pick(cpuPrefixes, 8) + pick(gpuPrefixes, 2) + pick(batteryPrefixes, 2)
    }

    /// `readings` maps sensor names to °C. Sensor names differ by Mac; the first letters say what
    /// they measure. Values outside a plausible range are sensors that are absent or broken.
    public init(readings: [String: Double]) {
        func values(_ prefixes: [String]) -> [Double] {
            readings.filter { key, value in value > 1 && value < 130 && prefixes.contains { key.hasPrefix($0) } }.map(\.value)
        }
        func average(_ list: [Double]) -> Double? { list.isEmpty ? nil : list.reduce(0, +) / Double(list.count) }
        let cores = values(Self.cpuPrefixes)
        cpu = average(cores)
        cpuPeak = cores.max()
        gpu = average(values(Self.gpuPrefixes))
        battery = average(values(Self.batteryPrefixes))
    }
}

public struct FanReading: Equatable, Sendable, Identifiable {
    public let index: Int
    public let rpm: Double, minimum: Double, maximum: Double
    public var id: Int { index }

    public init(index: Int, rpm: Double, minimum: Double, maximum: Double) {
        self.index = index
        self.rpm = rpm
        self.minimum = minimum
        self.maximum = maximum
    }

    /// Where the speed sits between the fan's slowest and fastest (0…1).
    public var fraction: Double {
        guard maximum > minimum else { return 0 }
        return min(max((rpm - minimum) / (maximum - minimum), 0), 1)
    }
}
