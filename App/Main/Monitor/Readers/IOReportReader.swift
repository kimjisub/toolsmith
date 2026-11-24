import Foundation
import IOKit
import ToolsmithKit

/// Reads the kernel's performance reports (libIOReport): energy used by the GPU, memory and
/// neural engine, and how long each core spent at each clock speed.
///
/// libIOReport has no public header; its functions are looked up by name, and every one missing
/// makes the reader unavailable rather than crash. It needs no special permission. On some systems
/// the CPU energy channels read zero without root; then the CPU power stays unknown.
final class IOReportReader {
    struct Reading {
        var gpuWatts: Double?
        var memoryWatts: Double?
        var neuralEngineWatts: Double?
        var cpuWatts: Double?
        /// Average MHz while running, per kind of core ("ECPU", "PCPU") and for the GPU.
        var cpuClusterMHz: [String: Double] = [:]
        var gpuMHz: Double?
    }

    private typealias CopyChannelsInGroup = @convention(c) (CFString, CFString?, UInt64, UInt64, UInt64) -> Unmanaged<CFMutableDictionary>?
    private typealias MergeChannels = @convention(c) (CFMutableDictionary, CFMutableDictionary, CFTypeRef?) -> Void
    private typealias CreateSubscription = @convention(c) (UnsafeRawPointer?, CFMutableDictionary, UnsafeMutablePointer<Unmanaged<CFMutableDictionary>?>, UInt64, CFTypeRef?) -> OpaquePointer?
    private typealias CreateSamples = @convention(c) (OpaquePointer, CFMutableDictionary, CFTypeRef?) -> Unmanaged<CFDictionary>?
    private typealias CreateSamplesDelta = @convention(c) (CFDictionary, CFDictionary, CFTypeRef?) -> Unmanaged<CFDictionary>?
    private typealias IntegerValue = @convention(c) (CFDictionary, Int32) -> Int64
    private typealias ChannelString = @convention(c) (CFDictionary) -> Unmanaged<CFString>?
    private typealias StateCount = @convention(c) (CFDictionary) -> Int32
    private typealias StateName = @convention(c) (CFDictionary, Int32) -> Unmanaged<CFString>?
    private typealias StateResidency = @convention(c) (CFDictionary, Int32) -> Int64

    private struct Functions {
        let createSamples: CreateSamples
        let delta: CreateSamplesDelta
        let integer: IntegerValue
        let name: ChannelString
        let group: ChannelString
        let unit: ChannelString
        let stateCount: StateCount
        let stateName: StateName
        let stateResidency: StateResidency
    }

    private let functions: Functions
    private let subscription: OpaquePointer
    private let channels: CFMutableDictionary
    private var previous: (sample: CFDictionary, time: TimeInterval)?
    private let cpuTables: [String: [Double]]
    private let gpuTable: [Double]

    init?() {
        guard let library = dlopen("/usr/lib/libIOReport.dylib", RTLD_NOW) else { return nil }
        func load<T>(_ name: String, as type: T.Type) -> T? { dlsym(library, name).map { unsafeBitCast($0, to: type) } }
        guard let copyGroup = load("IOReportCopyChannelsInGroup", as: CopyChannelsInGroup.self),
              let merge = load("IOReportMergeChannels", as: MergeChannels.self),
              let subscribe = load("IOReportCreateSubscription", as: CreateSubscription.self),
              let createSamples = load("IOReportCreateSamples", as: CreateSamples.self),
              let delta = load("IOReportCreateSamplesDelta", as: CreateSamplesDelta.self),
              let integer = load("IOReportSimpleGetIntegerValue", as: IntegerValue.self),
              let name = load("IOReportChannelGetChannelName", as: ChannelString.self),
              let group = load("IOReportChannelGetGroup", as: ChannelString.self),
              let unit = load("IOReportChannelGetUnitLabel", as: ChannelString.self),
              let stateCount = load("IOReportStateGetCount", as: StateCount.self),
              let stateName = load("IOReportStateGetNameForIndex", as: StateName.self),
              let stateResidency = load("IOReportStateGetResidency", as: StateResidency.self),
              let energy = copyGroup("Energy Model" as CFString, nil, 0, 0, 0)?.takeRetainedValue() else { return nil }
        if let cpu = copyGroup("CPU Stats" as CFString, "CPU Core Performance States" as CFString, 0, 0, 0)?.takeRetainedValue() { merge(energy, cpu, nil) }
        if let gpu = copyGroup("GPU Stats" as CFString, "GPU Performance States" as CFString, 0, 0, 0)?.takeRetainedValue() { merge(energy, gpu, nil) }
        var subscribed: Unmanaged<CFMutableDictionary>?
        guard let subscription = subscribe(nil, energy, &subscribed, 0, nil), let subscribed else { return nil }
        self.subscription = subscription
        channels = subscribed.takeRetainedValue()
        functions = Functions(createSamples: createSamples, delta: delta, integer: integer, name: name, group: group, unit: unit,
                              stateCount: stateCount, stateName: stateName, stateResidency: stateResidency)
        let tables = Self.clockTables()
        cpuTables = ["ECPU": tables["voltage-states1-sram"] ?? [], "PCPU": tables["voltage-states5-sram"] ?? []]
        gpuTable = tables["voltage-states9"] ?? []
    }

    /// Forgets the previous sample, so the next reading is not an average over a long pause.
    func restart() { previous = nil }

    /// What happened since the previous call. The first call only starts the clock and returns nil.
    func read() -> Reading? {
        guard let sample = functions.createSamples(subscription, channels, nil)?.takeRetainedValue() else { return nil }
        let now = ProcessInfo.processInfo.systemUptime
        defer { previous = (sample, now) }
        guard let previous, now - previous.time > 0.2,
              let delta = functions.delta(previous.sample, sample, nil)?.takeRetainedValue() as? [String: Any],
              let items = delta["IOReportChannels"] as? [CFDictionary] else { return nil }
        let seconds = now - previous.time
        var reading = Reading()
        var energy: [String: Double] = [:]
        var clusterStates: [String: [(String, Int64)]] = [:]
        var gpuStates: [(String, Int64)] = []
        for item in items {
            let group = functions.group(item)?.takeUnretainedValue() as String? ?? ""
            let name = functions.name(item)?.takeUnretainedValue() as String? ?? ""
            if group == "Energy Model" {
                let unit = functions.unit(item)?.takeUnretainedValue() as String? ?? ""
                energy[name] = Self.joules(functions.integer(item, 0), unit: unit)
            } else if group == "CPU Stats", let kind = ["ECPU", "PCPU"].first(where: { name.hasPrefix($0) }) {
                clusterStates[kind, default: []] += states(item)
            } else if group == "GPU Stats", name == "GPUPH" {
                gpuStates = states(item)
            }
        }
        func watts(_ joules: Double?) -> Double? { joules.map { $0 / seconds } }
        reading.gpuWatts = watts(energy["GPU Energy"])
        reading.memoryWatts = watts(energy.filter { $0.key.hasPrefix("DRAM") }.values.reduce(0, +))
        reading.neuralEngineWatts = watts(energy.filter { $0.key.hasPrefix("ANE") }.values.reduce(0, +))
        if let cpu = energy["CPU Energy"], cpu > 0 { reading.cpuWatts = cpu / seconds }
        for (kind, states) in clusterStates {
            // Several cores: add their residencies state by state, then average.
            var merged: [(String, Int64)] = []
            for (name, residency) in states {
                if let index = merged.firstIndex(where: { $0.0 == name }) { merged[index].1 += residency } else { merged.append((name, residency)) }
            }
            if let mhz = FrequencyEstimate.average(states: merged.map { (name: $0.0, residency: $0.1) }, table: cpuTables[kind] ?? []) {
                reading.cpuClusterMHz[kind] = mhz
            }
        }
        reading.gpuMHz = FrequencyEstimate.average(states: gpuStates.map { (name: $0.0, residency: $0.1) }, table: gpuTable)
        return reading
    }

    private func states(_ item: CFDictionary) -> [(String, Int64)] {
        (0..<functions.stateCount(item)).map { index in
            (functions.stateName(item, index)?.takeUnretainedValue() as String? ?? "", functions.stateResidency(item, index))
        }
    }

    private static func joules(_ value: Int64, unit: String) -> Double {
        switch unit {
        case "mJ": return Double(value) / 1e3
        case "uJ": return Double(value) / 1e6
        case "nJ": return Double(value) / 1e9
        default: return 0
        }
    }

    /// The power manager's clock tables, by property name.
    private static func clockTables() -> [String: [Double]] {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceNameMatching("pmgr"), &iterator) == kIOReturnSuccess else { return [:] }
        defer { IOObjectRelease(iterator) }
        var result: [String: [Double]] = [:]
        while case let entry = IOIteratorNext(iterator), entry != 0 {
            defer { IOObjectRelease(entry) }
            var properties: Unmanaged<CFMutableDictionary>?
            guard IORegistryEntryCreateCFProperties(entry, &properties, kCFAllocatorDefault, 0) == kIOReturnSuccess,
                  let dictionary = properties?.takeRetainedValue() as? [String: Any] else { continue }
            for (key, value) in dictionary where key.hasPrefix("voltage-states") {
                if let data = value as? Data { result[key] = FrequencyEstimate.table(fromVoltageStates: data) }
            }
        }
        return result
    }
}
