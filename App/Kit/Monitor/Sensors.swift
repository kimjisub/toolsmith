import Foundation

/// A named temperature, as the sensor list shows it.
public struct SensorReading: Equatable, Sendable, Identifiable {
    public let key: String
    public let label: String
    public let group: SensorGroup
    public let celsius: Double
    public var id: String { key }

    public init(key: String, label: String, group: SensorGroup, celsius: Double) {
        self.key = key
        self.label = label
        self.group = group
        self.celsius = celsius
    }
}

/// One group of sensors at a glance.
public struct SensorSummary: Equatable, Sendable, Identifiable {
    public let group: SensorGroup
    public let average: Double
    public let peak: Double
    public let readings: [SensorReading]
    public var id: Int { group.rawValue }
    public var name: String { name(locale: .app) }

    public func name(locale: Locale) -> String { group.name }
}

/// What a sensor measures, in the order the list shows groups.
public enum SensorGroup: Int, CaseIterable, Comparable, Sendable {
    case cpuPerformance, cpuEfficiency, gpu, memory, ssd, battery, wifi, thunderbolt, airflow

    public static func < (lhs: SensorGroup, rhs: SensorGroup) -> Bool { lhs.rawValue < rhs.rawValue }

    public var name: String { name(locale: .app) }

    public func name(locale: Locale) -> String {
        switch self {
        case .cpuPerformance: return localized("CPU Performance Cores", locale: locale)
        case .cpuEfficiency: return localized("CPU Efficiency Cores", locale: locale)
        case .gpu: return localized("Graphics", locale: locale)
        case .memory: return localized("Memory", locale: locale)
        case .ssd: return "SSD"
        case .battery: return localized("Battery", locale: locale)
        case .wifi: return "Wi-Fi"
        case .thunderbolt: return localized("Thunderbolt", locale: locale)
        case .airflow: return localized("Airflow", locale: locale)
        }
    }
}

/// Names the System Management Controller's temperature sensors.
///
/// Sensor keys differ from Mac to Mac, but their first two letters say what they measure. The
/// numbering within a group follows the keys' order, so "CPU Performance Cores 3" is the third such sensor,
/// not necessarily core 3.
public enum SensorCatalog {
    static let prefixes: [(String, SensorGroup)] = [
        ("Tp", .cpuPerformance), ("TC", .cpuPerformance), ("Te", .cpuEfficiency),
        ("Tg", .gpu), ("TG", .gpu), ("Tm", .memory), ("TH", .ssd), ("TN", .ssd), ("TB", .battery),
        ("TW", .wifi), ("TT", .thunderbolt), ("TI", .thunderbolt), ("Ta", .airflow), ("TA", .airflow),
    ]

    /// Readings outside this range are sensors that are absent, idle or broken.
    public static let plausible: ClosedRange<Double> = 1...130

    /// The sensors grouped, hottest group first within the catalog order: a Mac has dozens of
    /// sensors per group (an M3 Max has over a hundred for the CPU alone), too many to list flat.
    public static func summaries(_ readings: [SensorReading]) -> [SensorSummary] {
        Dictionary(grouping: readings, by: \.group).keys.sorted().map { group in
            let items = readings.filter { $0.group == group }
            let values = items.map(\.celsius)
            return SensorSummary(group: group, average: values.reduce(0, +) / Double(values.count), peak: values.max() ?? 0, readings: items)
        }
    }

    public static func group(of key: String) -> SensorGroup? {
        prefixes.first { key.hasPrefix($0.0) }?.1
    }

    /// `readings` maps keys to °C. Keys this catalog does not know and implausible values are left
    /// out; a group with one sensor gets no number.
    public static func readings(_ readings: [String: Double], locale: Locale = .app) -> [SensorReading] {
        var byGroup: [SensorGroup: [(String, Double)]] = [:]
        for (key, value) in readings where plausible.contains(value) {
            guard let group = group(of: key) else { continue }
            byGroup[group, default: []].append((key, value))
        }
        return byGroup.keys.sorted().flatMap { group -> [SensorReading] in
            let items = byGroup[group]!.sorted { $0.0 < $1.0 }
            return items.enumerated().map { index, item in
                SensorReading(key: item.0, label: items.count == 1 ? group.name(locale: locale) : "\(group.name(locale: locale)) \(index + 1)", group: group, celsius: item.1)
            }
        }
    }
}
