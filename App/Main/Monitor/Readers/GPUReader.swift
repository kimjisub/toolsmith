import Foundation
import IOKit

/// The graphics processor, as its driver reports it.
enum GPUReader {
    struct Reading {
        var utilization: Double?
        /// System memory the GPU is using (on Apple silicon memory is shared).
        var memoryInUse: UInt64?
    }

    static func read() -> Reading {
        var reading = Reading()
        forEachAccelerator { entry in
            guard let statistics = IORegistryEntryCreateCFProperty(entry, "PerformanceStatistics" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? [String: Any] else { return }
            if let usage = (statistics["Device Utilization %"] as? NSNumber)?.doubleValue { reading.utilization = max(reading.utilization ?? 0, usage) }
            if let memory = (statistics["In use system memory"] as? NSNumber)?.uint64Value { reading.memoryInUse = (reading.memoryInUse ?? 0) + memory }
        }
        return reading
    }

    /// Nanoseconds of GPU time each process has used since it started. Every app that draws with
    /// the GPU holds a connection to the driver that counts this.
    static func timeByProcess() -> [Int32: UInt64] {
        var result: [Int32: UInt64] = [:]
        forEachAccelerator { accelerator in
            var children: io_iterator_t = 0
            guard IORegistryEntryGetChildIterator(accelerator, kIOServicePlane, &children) == kIOReturnSuccess else { return }
            defer { IOObjectRelease(children) }
            while case let child = IOIteratorNext(children), child != 0 {
                defer { IOObjectRelease(child) }
                // "pid 416, WindowServer"
                guard let creator = IORegistryEntryCreateCFProperty(child, "IOUserClientCreator" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? String,
                      let pidText = creator.split(separator: ",").first?.split(separator: " ").last, let pid = Int32(pidText),
                      let usage = IORegistryEntryCreateCFProperty(child, "AppUsage" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? [[String: Any]] else { continue }
                let time = usage.compactMap { ($0["accumulatedGPUTime"] as? NSNumber)?.uint64Value }.reduce(0, +)
                result[pid, default: 0] += time
            }
        }
        return result
    }

    private static func forEachAccelerator(_ body: (io_registry_entry_t) -> Void) {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &iterator) == kIOReturnSuccess else { return }
        defer { IOObjectRelease(iterator) }
        while case let entry = IOIteratorNext(iterator), entry != 0 {
            body(entry)
            IOObjectRelease(entry)
        }
    }
}
