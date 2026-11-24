import Darwin
import Foundation
import ToolsmithKit

/// The kernel's own counters: CPU time, memory, load, uptime. Cheap; safe to call often.
enum KernelReader {
    /// Each `mach_host_self()` call takes another reference on the host port; one is enough.
    private static let host = mach_host_self()
    private static let pageSize: vm_size_t = {
        var size: vm_size_t = 0
        host_page_size(host, &size)
        return size
    }()

    static func cpuTicks() -> CPUTicks? {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { host_statistics(host, HOST_CPU_LOAD_INFO, $0, &count) }
        }
        guard result == KERN_SUCCESS else { return nil }
        return CPUTicks(user: UInt64(info.cpu_ticks.0), system: UInt64(info.cpu_ticks.1), idle: UInt64(info.cpu_ticks.2), nice: UInt64(info.cpu_ticks.3))
    }

    static func coreTicks() -> [CPUTicks] {
        var processorCount: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        guard host_processor_info(host, PROCESSOR_CPU_LOAD_INFO, &processorCount, &info, &infoCount) == KERN_SUCCESS, let info else { return [] }
        defer { vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info), vm_size_t(infoCount) * vm_size_t(MemoryLayout<integer_t>.stride)) }
        return (0..<Int(processorCount)).map { core in
            let base = core * Int(CPU_STATE_MAX)
            return CPUTicks(user: UInt64(UInt32(bitPattern: info[base + Int(CPU_STATE_USER)])),
                            system: UInt64(UInt32(bitPattern: info[base + Int(CPU_STATE_SYSTEM)])),
                            idle: UInt64(UInt32(bitPattern: info[base + Int(CPU_STATE_IDLE)])),
                            nice: UInt64(UInt32(bitPattern: info[base + Int(CPU_STATE_NICE)])))
        }
    }

    /// The kinds of cores, fastest first ("Performance", "Efficiency"; "Super" on newer chips).
    static func coreClusters() -> [CoreCluster] {
        let levels = sysctlInt("hw.nperflevels") ?? 0
        return (0..<levels).compactMap { level in
            guard let count = sysctlInt("hw.perflevel\(level).logicalcpu"), count > 0 else { return nil }
            return CoreCluster(name: sysctlString("hw.perflevel\(level).name") ?? String(localized: "Cores"), count: count)
        }
    }

    /// Memory use and the page traffic counters (pages read in from disk, written out to swap).
    static func memory() -> (MemoryBreakdown, pageIns: UInt64, pageOuts: UInt64) {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { host_statistics64(host, HOST_VM_INFO64, $0, &count) }
        }
        guard result == KERN_SUCCESS else { return (MemoryBreakdown(), 0, 0) }
        var swap = xsw_usage()
        var swapSize = MemoryLayout<xsw_usage>.size
        sysctlbyname("vm.swapusage", &swap, &swapSize, nil, 0)
        var level: Int32 = 0
        var levelSize = MemoryLayout<Int32>.size
        sysctlbyname("kern.memorystatus_level", &level, &levelSize, nil, 0)
        let breakdown = MemoryBreakdown(total: ProcessInfo.processInfo.physicalMemory, internalPages: UInt64(stats.internal_page_count),
                                        purgeablePages: UInt64(stats.purgeable_count), externalPages: UInt64(stats.external_page_count),
                                        wiredPages: UInt64(stats.wire_count), compressorPages: UInt64(stats.compressor_page_count),
                                        pageSize: UInt64(pageSize), swapUsed: swap.xsu_used, freeLevel: Int(level))
        return (breakdown, UInt64(stats.pageins) * UInt64(pageSize), UInt64(stats.pageouts) * UInt64(pageSize))
    }

    static func loadAverage() -> [Double] {
        var values = [Double](repeating: 0, count: 3)
        return getloadavg(&values, 3) == 3 ? values : []
    }

    static func uptime() -> TimeInterval {
        var boot = timeval()
        var size = MemoryLayout<timeval>.size
        guard sysctlbyname("kern.boottime", &boot, &size, nil, 0) == 0 else { return 0 }
        return Date().timeIntervalSince1970 - Double(boot.tv_sec)
    }

    static func sysctlInt(_ name: String) -> Int? {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        return sysctlbyname(name, &value, &size, nil, 0) == 0 ? Int(value) : nil
    }

    static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        return String(cString: buffer)
    }
}
