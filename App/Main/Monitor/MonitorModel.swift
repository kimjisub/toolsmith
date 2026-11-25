import AppKit
import Combine
import ToolsmithKit

/// The parts of the monitor, each a card on the dashboard with its own details.
enum MonitorSection: String, CaseIterable, Identifiable {
    case cpu, sensors, memory, disk, network, battery
    var id: String { rawValue }
}

/// What the network details show about the connection.
struct NetworkConnection: Sendable {
    var interface: String?
    var isWiFi = false
    var wifiName: String?
    var addresses: [InterfaceAddress] = []
    var vpns: [String] = []
}

/// Keeps the system readings current: the light ones always (the menu bar and the history need
/// them), everything else only while the monitor is open.
@MainActor final class MonitorModel: ObservableObject {
    @Published private(set) var snapshot = SystemSnapshot()
    @Published private(set) var cpuUserHistory = History(capacity: 90)
    @Published private(set) var cpuSystemHistory = History(capacity: 90)
    @Published private(set) var downloadHistory = History(capacity: 90)
    @Published private(set) var uploadHistory = History(capacity: 90)
    @Published private(set) var memoryHistory = History(capacity: 90)
    @Published private(set) var powerHistory = History(capacity: 90)
    @Published private(set) var diskReadHistory = History(capacity: 90)
    @Published private(set) var diskWriteHistory = History(capacity: 90)
    /// The CPU load the icon follows, updated even when the monitor is closed.
    @Published private(set) var load: Double = 0
    /// The section whose details are showing.
    @Published private(set) var detail: MonitorSection?
    @Published private(set) var connection = NetworkConnection()
    @Published private(set) var accessories: [AccessoryBattery] = []
    @Published private(set) var energyMode: EnergyMode?
    /// Session peaks, shown under the network graph.
    @Published private(set) var peakDownload: Double = 0
    @Published private(set) var peakUpload: Double = 0

    let processes = ProcessMonitor()
    let publicAddress = PublicAddressLookup()

    private let sampler = SystemSampler()
    /// Sampling touches the kernel and the sensor chip; it, and the history file, stay off the main thread.
    private let queue = DispatchQueue(label: "\(AppIdentity.bundleID).monitor", qos: .utility)
    private let store = try? MetricHistoryStore(directory: SettingsStore.supportDirectory.appendingPathComponent("monitor", isDirectory: true))
    private var recent = RecentReadings()
    private var timer: Timer?
    private var running = false
    private var isOpen = false
    private var ticks = 0
    /// A menu bar meter is showing: the closed reading comes every 3 seconds instead of 5.
    var meterShown = false {
        didSet { if meterShown != oldValue, running { schedule() } }
    }

    init() {
        let center = NSWorkspace.shared.notificationCenter
        for (name, asleep) in [(NSWorkspace.screensDidSleepNotification, true), (NSWorkspace.screensDidWakeNotification, false)] {
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.displayAsleep = asleep }
            }
        }
    }

    private var prepared = false

    /// Starts reading (the feature was switched on). The first time, the last hour of readings is
    /// brought back from disk first, so the graphs carry on from before the app was reopened.
    func start() {
        guard !running else { return }
        running = true
        if !prepared {
            prepared = true
            queue.async { [weak self, sampler, store] in
                sampler.prepare()
                let readings = store?.restore(now: Date().timeIntervalSince1970) ?? []
                DispatchQueue.main.async { self?.restore(readings) }
            }
        }
        schedule()
        tick()
    }

    /// Stops every reading and writes the minute in progress (the feature was switched off, or the app quits).
    func stop() {
        guard running else { return }
        running = false
        timer?.invalidate()
        timer = nil
        isOpen = false
        showDetail(nil)
        flush()
    }

    /// Nobody sees the menu bar while the display sleeps: read just often enough for the history.
    private var displayAsleep = false {
        didSet {
            guard displayAsleep != oldValue, running else { return }
            schedule()
            if !displayAsleep { tick() }
        }
    }

    /// The monitor appeared or went away.
    func setOpen(_ open: Bool) {
        guard open != isOpen, running else { return }
        isOpen = open
        if open { queue.async { [sampler] in sampler.reset() } } else { showDetail(nil) }
        schedule()
        tick()
    }

    /// Shows a section's details (nil hides them) and starts what only they need.
    func showDetail(_ section: MonitorSection?) {
        guard section != detail else { return }
        detail = section
        switch section {
        case .cpu: processes.setFeeds([.top(.cpu), .gpu])
        case .memory: processes.setFeeds([.top(.memory)])
        case .battery: processes.setFeeds([.top(.energy)])
        case .network: processes.setFeeds([.network])
        default: processes.setFeeds([])
        }
        if section == .network { refreshConnection() }
        if section == .battery { refreshBatteryExtras() }
    }

    /// Whether the network details may ask Cloudflare for the public address (a setting).
    var allowsPublicAddressLookup: () -> Bool = { true }

    /// Deletes the recorded history, in memory and on disk.
    func clearHistory() {
        recent = RecentReadings()
        for metric in Metric.allCases { clearGraph(metric) }
        queue.async { [store] in store?.removeAll() }
    }

    /// Writes the minute in progress before the app quits.
    func flush() {
        queue.sync { store?.flush() }
    }

    /// `count` averages over `range`, oldest first, per metric. nil where nothing was recorded.
    func history(_ metrics: [Metric], range: HistoryRange, count: Int) async -> [Metric: [Double?]] {
        let recent = self.recent
        return await withCheckedContinuation { continuation in
            queue.async { [store] in
                let end = Date().timeIntervalSince1970
                let start = end - range.seconds
                var result: [Metric: [Double?]] = [:]
                for metric in metrics {
                    let points = range.usesRecentReadings ? recent.values(metric, since: start) : (store?.values(metric, since: start) ?? [])
                    result[metric] = HistoryBuckets.average(points, start: start, end: end, count: count)
                }
                continuation.resume(returning: result)
            }
        }
    }

    private func schedule() {
        timer?.invalidate()
        // Every second while someone is looking; otherwise often enough for the menu bar and the history.
        let timer = Timer(timeInterval: isOpen ? 1 : displayAsleep ? 30 : (meterShown ? 3 : 5), repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        timer.tolerance = isOpen ? 0.2 : 1
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func tick() {
        let full = isOpen
        ticks += 1
        if detail == .network, ticks % 5 == 0 { refreshConnection() }
        queue.async { [weak self, sampler, store] in
            let snapshot = sampler.sample(full: full)
            let reading = Reading(time: Date().timeIntervalSince1970, Self.metrics(snapshot))
            store?.add(reading)
            DispatchQueue.main.async { self?.apply(snapshot, reading: reading) }
        }
    }

    nonisolated private static func metrics(_ s: SystemSnapshot) -> [(Metric, Double)] {
        var values: [(Metric, Double)] = [(.memoryPressure, s.memory.pressure), (.memoryUsed, s.memory.usedPercent)]
        if s.ratesMeasured {
            values += [(.cpuUser, s.cpu.user), (.cpuSystem, s.cpu.system), (.download, s.downloadRate), (.upload, s.uploadRate),
                       (.diskRead, s.diskReadRate), (.diskWrite, s.diskWriteRate)]
        }
        if let gpu = s.gpu { values.append((.gpu, gpu)) }
        if let power = s.power.system { values.append((.systemPower, power)) }
        if let battery = s.battery {
            values.append((.batteryLevel, battery.level))
            if let temperature = battery.temperature { values.append((.batteryTemperature, temperature)) }
        }
        if let cpu = s.temperatures.cpu { values.append((.cpuTemperature, cpu)) }
        return values
    }

    /// Readings brought back from disk at launch, before the first new one.
    private func restore(_ readings: [Reading]) {
        recent = RecentReadings(readings)
        for reading in readings.suffix(cpuUserHistory.capacity) { record(reading) }
    }

    /// Adds a reading to the small graphs.
    private func record(_ reading: Reading) {
        for (metric, value) in reading.values { updateGraph(metric) { $0.push(value, at: reading.time) } }
    }

    private func clearGraph(_ metric: Metric) {
        updateGraph(metric) { $0 = History(capacity: $0.capacity) }
    }

    /// The small graph that shows `metric`, if there is one.
    private func updateGraph(_ metric: Metric, _ change: (inout History) -> Void) {
        switch metric {
        case .cpuUser: change(&cpuUserHistory)
        case .cpuSystem: change(&cpuSystemHistory)
        case .download: change(&downloadHistory)
        case .upload: change(&uploadHistory)
        case .memoryUsed: change(&memoryHistory)
        case .systemPower: change(&powerHistory)
        case .diskRead: change(&diskReadHistory)
        case .diskWrite: change(&diskWriteHistory)
        case .gpu, .memoryPressure, .batteryLevel, .batteryTemperature, .cpuTemperature: break
        }
    }

    private func apply(_ new: SystemSnapshot, reading: Reading) {
        load = new.cpu.total
        for (metric, value) in reading.values { recent.add(metric, value, at: reading.time) }
        record(reading)
        peakDownload = max(peakDownload, new.downloadRate)
        peakUpload = max(peakUpload, new.uploadRate)
        if isOpen {
            snapshot = new
        } else {
            // Keep the last full readings; refresh only what the light reading measured.
            var merged = snapshot
            merged.cpu = new.cpu
            merged.memory = new.memory
            merged.downloadRate = new.downloadRate
            merged.uploadRate = new.uploadRate
            merged.diskReadRate = new.diskReadRate
            merged.diskWriteRate = new.diskWriteRate
            merged.volume = new.volume
            merged.gpu = new.gpu
            merged.temperatures = new.temperatures
            merged.power.system = new.power.system
            merged.power.adapter = new.power.adapter
            merged.power.battery = new.power.battery
            merged.battery = new.battery
            snapshot = merged
        }
    }

    private func refreshConnection() {
        Task { [weak self] in
            let connection = await Self.readConnection()
            self?.connection = connection
            if self?.allowsPublicAddressLookup() == true { self?.publicAddress.refreshIfNeeded(interface: connection.interface) }
        }
    }

    /// Reads the connection off the main thread (a nonisolated async function runs elsewhere).
    nonisolated private static func readConnection() async -> NetworkConnection {
            var connection = NetworkConnection()
            let addresses = NetworkReader.addresses()
            connection.interface = VPNDetection.physicalInterface(primary: NetworkReader.primaryInterface(), addresses: addresses)
            connection.addresses = addresses.filter { $0.interface == connection.interface }
            connection.vpns = VPNDetection.names(tunnelAddresses: addresses)
            if let interface = connection.interface, NetworkReader.isWiFi(interface) {
                connection.isWiFi = true
                connection.wifiName = NetworkReader.wifiName()
            }
            return connection
    }

    private func refreshBatteryExtras() {
        Task { [weak self] in
            let (accessories, mode) = await Self.readBatteryExtras()
            self?.accessories = accessories
            self?.energyMode = mode
        }
    }

    nonisolated private static func readBatteryExtras() async -> ([AccessoryBattery], EnergyMode?) {
        (BatteryReader.accessories(), BatteryReader.energyMode())
    }
}
