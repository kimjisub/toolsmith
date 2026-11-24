import Foundation
import IOKit

/// The startup disk: its space, and the bytes read and written on every disk since startup.
enum DiskReader {
    struct Volume: Sendable {
        var name = "Macintosh HD"
        var total: Int64 = 0
        var available: Int64 = 0

        var usedFraction: Double { total > 0 ? Double(max(0, total - available)) / Double(total) : 0 }
    }

    static func startupVolume() -> Volume {
        var volume = Volume()
        let keys: Set<URLResourceKey> = [.volumeNameKey, .volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey]
        guard let values = try? URL(fileURLWithPath: "/").resourceValues(forKeys: keys) else { return volume }
        volume.name = values.volumeName ?? volume.name
        volume.total = Int64(values.volumeTotalCapacity ?? 0)
        volume.available = values.volumeAvailableCapacityForImportantUsage ?? 0
        return volume
    }

    static func bytes() -> (read: UInt64, written: UInt64) {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOBlockStorageDriver"), &iterator) == kIOReturnSuccess else { return (0, 0) }
        defer { IOObjectRelease(iterator) }
        var read: UInt64 = 0, written: UInt64 = 0
        while case let entry = IOIteratorNext(iterator), entry != 0 {
            defer { IOObjectRelease(entry) }
            guard let statistics = IORegistryEntryCreateCFProperty(entry, "Statistics" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? [String: Any] else { continue }
            read += (statistics["Bytes (Read)"] as? NSNumber)?.uint64Value ?? 0
            written += (statistics["Bytes (Write)"] as? NSNumber)?.uint64Value ?? 0
        }
        return (read, written)
    }
}
