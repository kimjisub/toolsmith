import Foundation
import IOKit
import IOKit.ps
import ToolsmithKit

/// The battery, its charger and Bluetooth accessories' batteries.
enum BatteryReader {
    /// Level and charging state from the power source list (cheap). nil on a Mac without a battery.
    static func battery() -> BatteryInfo? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        var battery: BatteryInfo?
        for source in list {
            guard let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType else { continue }
            var result = BatteryInfo()
            let current = (description[kIOPSCurrentCapacityKey] as? Int) ?? 0
            let maximum = max((description[kIOPSMaxCapacityKey] as? Int) ?? 100, 1)
            result.level = Double(current) / Double(maximum) * 100
            result.isCharging = (description[kIOPSIsChargingKey] as? Bool) ?? false
            result.onAdapter = (description[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue
            result.isFull = (description[kIOPSIsChargedKey] as? Bool) ?? false
            let minutes = (description[result.isCharging ? kIOPSTimeToFullChargeKey : kIOPSTimeToEmptyKey] as? Int) ?? -1
            result.minutesRemaining = minutes > 0 ? minutes : nil
            result.condition = description[kIOPSBatteryHealthKey] as? String
            battery = result
        }
        return battery
    }

    /// What the charge controller knows beyond the level: capacity, cycles, temperature, the adapter.
    struct Details {
        var cycleCount: Int?
        var designCapacity: Int?
        var maximumCapacity: Int?
        var temperature: Double?
        var adapterWatts: Int?

        func apply(to battery: inout BatteryInfo) {
            battery.cycleCount = cycleCount
            battery.designCapacity = designCapacity
            battery.maximumCapacity = maximumCapacity
            battery.temperature = temperature
            battery.adapterWatts = adapterWatts
        }
    }

    /// Reads the controller's whole property list (large); the open monitor asks twice a minute at most.
    /// Newer systems keep some of these inside "BatteryData".
    static func details() -> Details {
        var details = Details()
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return details }
        defer { IOObjectRelease(service) }
        var properties: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0) == kIOReturnSuccess,
              let top = properties?.takeRetainedValue() as? [String: Any] else { return details }
        let nested = top["BatteryData"] as? [String: Any] ?? [:]
        func int(_ key: String) -> Int? { (top[key] as? Int) ?? (nested[key] as? Int) }
        details.cycleCount = int("CycleCount")
        details.designCapacity = int("DesignCapacity")
        details.maximumCapacity = int("AppleRawMaxCapacity") ?? int("NominalChargeCapacity")
        // Hundredths of a degree.
        let temperatures = [nested["Temperature"], top["Temperature"], top["VirtualTemperature"]].compactMap { ($0 as? NSNumber)?.intValue }
        if let raw = temperatures.first(where: { $0 > 0 }) { details.temperature = Double(raw) / 100 }
        details.adapterWatts = (top["AdapterDetails"] as? [String: Any])?["Watts"] as? Int
        return details
    }

    /// Battery power in watts: positive while charging, negative while the Mac runs on it.
    static func batteryWatts() -> Double? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        func int(_ key: String) -> Int? { IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? Int }
        guard let millivolts = int("Voltage"), let milliamps = int("InstantAmperage") ?? int("Amperage") else { return nil }
        // The amperage is a signed 64-bit value that some systems hand over as unsigned.
        let signed = milliamps > Int(Int32.max) ? milliamps - (1 << 32) : milliamps
        return Double(millivolts) * Double(signed) / 1_000_000
    }

    /// Keyboards, trackpads and mice that report a battery level.
    static func accessories() -> [AccessoryBattery] {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("AppleDeviceManagementHIDEventService"), &iterator) == kIOReturnSuccess else { return [] }
        defer { IOObjectRelease(iterator) }
        var result: [AccessoryBattery] = []
        while case let entry = IOIteratorNext(iterator), entry != 0 {
            defer { IOObjectRelease(entry) }
            guard let level = IORegistryEntryCreateCFProperty(entry, "BatteryPercent" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? Int,
                  let name = IORegistryEntryCreateCFProperty(entry, "Product" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? String,
                  !result.contains(where: { $0.name == name }) else { continue }
            result.append(AccessoryBattery(name: name, level: Double(level)))
        }
        return result.sorted { $0.name < $1.name }
    }

    /// The energy mode, from `pmset -g`. Spawns a process; call rarely, off the main thread.
    static func energyMode() -> EnergyMode? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        process.arguments = ["-g"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return EnergyMode.parse(pmset: String(decoding: data, as: UTF8.self))
    }
}
