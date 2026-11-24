import Foundation

/// Average clock speed from how long a processor spent in each performance state.
///
/// The kernel counts, per core, the time spent in each state: idle and off states, then one state
/// per step of the clock table, slowest first ("V0P5", "V1P4", … or "P1", "P2", …). The clock of
/// each step comes from the power manager's table. Averaging the clock over the time the core was
/// running (idle time left out) gives the speed it ran at.
public enum FrequencyEstimate {
    static let inactiveStates: Set<String> = ["IDLE", "DOWN", "OFF"]

    /// `states` are (name, time) in the kernel's order; `table` is MHz per running step, slowest
    /// first. nil when the core never ran in the interval or the table does not fit.
    public static func average(states: [(name: String, residency: Int64)], table: [Double]) -> Double? {
        let running = states.filter { !inactiveStates.contains($0.name.uppercased()) }
        guard !running.isEmpty, !table.isEmpty else { return nil }
        var time = 0.0, weighted = 0.0
        for (index, state) in running.enumerated() where state.residency > 0 {
            // More states than table rows: the extra ones run at the top speed.
            let mhz = table[min(index, table.count - 1)]
            time += Double(state.residency)
            weighted += Double(state.residency) * mhz
        }
        return time > 0 ? weighted / time : nil
    }

    /// The clock table out of the power manager's "voltage-states" property: little-endian
    /// (frequency, voltage) pairs of 32-bit numbers. Zero frequencies (off) are dropped. Older
    /// chips give Hz, newer ones kHz; either way the result is MHz.
    public static func table(fromVoltageStates data: Data) -> [Double] {
        let bytes = [UInt8](data)
        var result: [Double] = []
        var offset = 0
        while offset + 8 <= bytes.count {
            let raw = UInt32(bytes[offset]) | UInt32(bytes[offset + 1]) << 8 | UInt32(bytes[offset + 2]) << 16 | UInt32(bytes[offset + 3]) << 24
            if raw > 0 { result.append(raw >= 10_000_000 ? Double(raw) / 1_000_000 : Double(raw) / 1_000) }
            offset += 8
        }
        return result
    }
}
