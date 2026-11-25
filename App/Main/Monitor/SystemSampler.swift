import Foundation
import ToolsmithKit

/// One look at how the Mac is doing.
struct SystemSnapshot: Sendable {
    var cpu = CPUUsage()
    /// Whether the CPU load and the disk and network rates were measured. The first reading has
    /// nothing to compare with: those stay zero and are not history.
    var ratesMeasured = false
    var cores: [Double] = []
    /// The kinds of cores, fastest first, and which kind each entry of `cores` is.
    var clusters: [CoreCluster] = []
    var coreCluster: [Int] = []
    /// Average clock while running, MHz: per kind of core ("PCPU", "ECPU") and the GPU.
    var cpuClusterMHz: [String: Double] = [:]
    var gpuMHz: Double?
    var loadAverage: [Double] = []
    var uptime: TimeInterval = 0
    var memory = MemoryBreakdown()
    var pageInRate: Double = 0
    var pageOutRate: Double = 0
    var gpu: Double?
    var gpuMemory: UInt64?
    var volume = DiskReader.Volume()
    var diskReadRate: Double = 0
    var diskWriteRate: Double = 0
    var downloadRate: Double = 0
    var uploadRate: Double = 0
    var temperatures = TemperatureSummary(readings: [:])
    var sensors: [SensorReading] = []
    var fans: [FanReading] = []
    var power = PowerBreakdown()
    var battery: BatteryInfo?

    /// The clock the CPU header shows: the fastest kind of core that ran.
    var cpuMHz: Double? { cpuClusterMHz.values.max() }
}

/// Reads the system's counters and sensors. Rates come from the difference between two readings,
/// so the first snapshot after a pause shows zero for them.
/// Not thread-safe: `MonitorModel` calls it from one serial queue only.
final class SystemSampler: @unchecked Sendable {
    private var lastCPU: CPUTicks?
    private var lastCores: [CPUTicks] = []
    private var lastCounters: (values: [String: UInt64], at: TimeInterval)?
    private let sensors = SensorReader()
    private lazy var report = IOReportReader()
    private var clusters: [CoreCluster] = []
    /// The startup disk's space changes slowly; it is read at most once a minute.
    private var volume: (value: DiskReader.Volume, at: TimeInterval)?
    /// What the open monitor reads every second tick only (every sensor, fans, clocks, part power):
    /// the slowest readings, and none of them changes fast enough to need more.
    private var fullTicks = 0
    private var slow = SlowReadings()
    /// The battery controller's details (capacity, cycles) change over days; read twice a minute at most.
    private var batteryDetails: (details: BatteryReader.Details, at: TimeInterval)?

    private struct SlowReadings {
        var sensors: [SensorReading] = []
        var fans: [FanReading] = []
        var report: IOReportReader.Reading?
    }

    /// Finds this Mac's sensors and core layout. Slow; call once, off the main thread.
    func prepare() {
        sensors.prepare()
        clusters = KernelReader.coreClusters()
    }

    /// `full` also reads what only the open monitor shows (each core, every sensor, clocks,
    /// battery details). The light reading is what the menu bar and the history need.
    func sample(full: Bool) -> SystemSnapshot {
        var snapshot = SystemSnapshot()
        if let ticks = KernelReader.cpuTicks() {
            if let lastCPU {
                snapshot.cpu = CPUUsage.between(lastCPU, ticks)
                snapshot.ratesMeasured = lastCounters != nil
            }
            lastCPU = ticks
        }
        let (memory, pageIns, pageOuts) = KernelReader.memory()
        snapshot.memory = memory
        let disk = DiskReader.bytes()
        let network = NetworkReader.bytes()
        let now = ProcessInfo.processInfo.systemUptime
        let counters = ["diskRead": disk.read, "diskWrite": disk.written, "down": network.received, "up": network.sent, "pageIn": pageIns, "pageOut": pageOuts]
        if let last = lastCounters {
            let rates = CounterRates.rates(before: last.values, after: counters, seconds: now - last.at)
            snapshot.diskReadRate = rates["diskRead"] ?? 0
            snapshot.diskWriteRate = rates["diskWrite"] ?? 0
            snapshot.downloadRate = rates["down"] ?? 0
            snapshot.uploadRate = rates["up"] ?? 0
            snapshot.pageInRate = rates["pageIn"] ?? 0
            snapshot.pageOutRate = rates["pageOut"] ?? 0
        }
        lastCounters = (counters, now)
        if volume == nil || now - volume!.at > 60 { volume = (DiskReader.startupVolume(), now) }
        snapshot.volume = volume?.value ?? DiskReader.Volume()
        let gpu = GPUReader.read()
        snapshot.gpu = gpu.utilization
        snapshot.gpuMemory = gpu.memoryInUse
        let slowTick = full && fullTicks % 2 == 0
        if full { fullTicks += 1 }
        let sensorReading = sensors.read(full: slowTick)
        snapshot.temperatures = sensorReading.summary
        snapshot.power.system = sensorReading.systemWatts
        snapshot.power.adapter = sensorReading.adapterWatts
        snapshot.power.battery = BatteryReader.batteryWatts()
        snapshot.battery = BatteryReader.battery()
        if full, snapshot.battery != nil {
            if batteryDetails == nil || now - batteryDetails!.at > 30 { batteryDetails = (BatteryReader.details(), now) }
            batteryDetails?.details.apply(to: &snapshot.battery!)
        }
        // Newer systems keep the battery's own temperature from apps; its SMC sensors still read.
        if snapshot.battery?.temperature == nil { snapshot.battery?.temperature = sensorReading.summary.battery }
        guard full else { return snapshot }

        let cores = KernelReader.coreTicks()
        if cores.count == lastCores.count { snapshot.cores = zip(lastCores, cores).map { CPUTicks.usage(from: $0, to: $1) } }
        lastCores = cores
        snapshot.clusters = clusters
        snapshot.coreCluster = CoreCluster.assign(clusters: clusters, coreCount: cores.count)
        snapshot.loadAverage = KernelReader.loadAverage()
        snapshot.uptime = KernelReader.uptime()
        if slowTick {
            slow.sensors = sensorReading.sensors
            slow.fans = sensorReading.fans
            if let reading = report?.read() { slow.report = reading }
        }
        snapshot.sensors = slow.sensors
        snapshot.fans = slow.fans
        if let reading = slow.report {
            snapshot.power.cpu = reading.cpuWatts
            snapshot.power.gpu = reading.gpuWatts
            snapshot.power.memory = reading.memoryWatts
            snapshot.power.neuralEngine = reading.neuralEngineWatts
            snapshot.cpuClusterMHz = reading.cpuClusterMHz
            snapshot.gpuMHz = reading.gpuMHz
        }
        return snapshot
    }

    /// Forget the per-core readings, so the next ones are not averaged over a long pause.
    func reset() {
        lastCores = []
        fullTicks = 0
        slow = SlowReadings()
        report?.restart()
    }
}
