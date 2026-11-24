import Foundation
import ToolsmithKit

/// Temperatures, fans and the power figures the System Management Controller keeps.
final class SensorReader {
    struct Reading {
        var summary = TemperatureSummary(readings: [:])
        var sensors: [SensorReading] = []
        var fans: [FanReading] = []
        /// Watts the whole Mac draws, and what comes in from the adapter.
        var systemWatts: Double?
        var adapterWatts: Double?
    }

    private let smc = SMC()
    private var keys: [String]?
    private var summaryKeys: [String] = []

    /// Finds this Mac's sensors. Slow (thousands of calls); once, off the main thread.
    func prepare() {
        guard keys == nil else { return }
        let found = smc?.temperatureKeys() ?? []
        keys = found
        var readings: [String: Double] = [:]
        for key in found where TemperatureSummary.wanted(key) {
            if let value = smc?.value(key) { readings[key] = value }
        }
        summaryKeys = TemperatureSummary.lightKeys(readings)
    }

    /// `full` reads every sensor and the fans; otherwise only what the summary and the menu bar need.
    func read(full: Bool) -> Reading {
        var reading = Reading()
        guard let smc else { return reading }
        var values: [String: Double] = [:]
        for key in full ? (keys ?? []) : summaryKeys {
            if let value = smc.value(key) { values[key] = value }
        }
        // The summary always comes from the same sensors, so it does not jump between a full and a light reading.
        reading.summary = TemperatureSummary(readings: full ? values.filter { summaryKeys.contains($0.key) } : values)
        if full {
            reading.sensors = SensorCatalog.readings(values)
            reading.fans = smc.fans()
        }
        // Apple silicon: PSTR is the system total, PDTR the power coming in.
        reading.systemWatts = smc.value("PSTR").flatMap { $0 > 0 && $0 < 1_000 ? $0 : nil }
        reading.adapterWatts = smc.value("PDTR").flatMap { $0 >= 0 && $0 < 1_000 ? $0 : nil }
        return reading
    }
}
