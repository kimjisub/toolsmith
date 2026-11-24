import AppKit
import Darwin
import ToolsmithKit

/// Which processes use the most, while someone is looking.
///
/// CPU, memory and energy come from `top`, which can see every process (an app cannot read other
/// users' processes, such as WindowServer, by itself). Network comes from `nettop`, GPU time from
/// the graphics driver. Each tool runs only while a detail view that shows it is open: `top`
/// costs a few percent of one core.
@MainActor final class ProcessMonitor: ObservableObject {
    enum Feed: Hashable { case top(TopOrder), network, gpu }

    /// What `top` ranks by; it then prints only the rows that list needs.
    enum TopOrder: String { case cpu, memory = "mem", energy = "power" }

    @Published private(set) var cpu: [UsageEntry] = []
    @Published private(set) var memory: [UsageEntry] = []
    @Published private(set) var energy: [UsageEntry] = []
    @Published private(set) var gpu: [UsageEntry] = []
    /// Bytes per second received and sent per app.
    @Published private(set) var network: [(entry: UsageEntry, received: Double, sent: Double)] = []

    static let limit = 15
    private var top: StreamingTool?
    private var topOrder: TopOrder?
    private var nettop: StreamingTool?
    private var gpuTimer: Timer?
    private var lastGPU: (times: [Int32: UInt64], at: TimeInterval)?
    private var lastNetwork: (bytes: [Int32: (UInt64, UInt64)], at: TimeInterval)?
    private let identities = ProcessIdentities()

    func setFeeds(_ feeds: Set<Feed>) {
        let order = feeds.lazy.compactMap { feed -> TopOrder? in if case .top(let order) = feed { return order } else { return nil } }.first
        if let order { startTop(order) } else { top?.stop(); top = nil; topOrder = nil }
        if feeds.contains(.network) { startNettop() } else { nettop?.stop(); nettop = nil; lastNetwork = nil }
        if feeds.contains(.gpu) { startGPU() } else { gpuTimer?.invalidate(); gpuTimer = nil; lastGPU = nil }
    }

    private func startTop(_ order: TopOrder) {
        guard topOrder != order else { return }
        top?.stop()
        topOrder = order
        var parser = TopStreamParser()
        var blocks = 0
        // Every 3 seconds, only the top rows by the one number shown: top itself costs CPU, and most of
        // it is printing and reading every process.
        let arguments = ["-l", "0", "-s", "3", "-o", order.rawValue, "-n", "\(Self.topRows)", "-stats", "pid,cpu,mem,power,command"]
        top = StreamingTool(path: "/usr/bin/top", arguments: arguments) { [weak self] line in
            guard let rows = parser.feed(line) else { return }
            blocks += 1
            // The first block's CPU figures are always zero.
            guard blocks > 1 else { return }
            Task { @MainActor in self?.applyTop(rows, order: order) }
        }
    }

    /// Rows asked of top: more than the list shows, because helpers are added to their app.
    private static let topRows = 100

    private func applyTop(_ rows: [ProcessSample], order: TopOrder) {
        let identity = identities.resolver(commands: Dictionary(rows.map { ($0.pid, $0.command) }, uniquingKeysWith: { first, _ in first }))
        switch order {
        case .cpu: cpu = UsageRanking.top(rows.map { ($0.pid, $0.cpu) }, limit: Self.limit, identity: identity)
        case .memory: memory = UsageRanking.top(rows.map { ($0.pid, Double($0.memory)) }, limit: Self.limit, identity: identity)
        case .energy: energy = UsageRanking.top(rows.map { ($0.pid, $0.energy) }, limit: Self.limit, identity: identity)
        }
    }

    private func startNettop() {
        guard nettop == nil else { return }
        var parser = NettopStreamParser()
        nettop = StreamingTool(path: "/usr/bin/nettop", arguments: ["-P", "-L", "0", "-s", "3", "-n", "-x", "-J", "bytes_in,bytes_out"]) { [weak self] line in
            guard let rows = parser.feed(line) else { return }
            Task { @MainActor in self?.applyNetwork(rows) }
        }
    }

    private func applyNetwork(_ rows: [Int32: (name: String, received: UInt64, sent: UInt64)]) {
        let now = ProcessInfo.processInfo.systemUptime
        let bytes = rows.mapValues { ($0.received, $0.sent) }
        defer { lastNetwork = (bytes, now) }
        guard let last = lastNetwork else { return }
        let seconds = now - last.at
        let received = CounterRates.rates(before: last.bytes.mapValues(\.0), after: bytes.mapValues(\.0), seconds: seconds)
        let sent = CounterRates.rates(before: last.bytes.mapValues(\.1), after: bytes.mapValues(\.1), seconds: seconds)
        let identity = identities.resolver(commands: rows.mapValues(\.name))
        // Rank by both directions together, then split each app's total back out.
        let ranked = UsageRanking.top(rows.keys.map { ($0, (received[$0] ?? 0) + (sent[$0] ?? 0)) }, limit: 8, identity: identity)
        network = ranked.map { entry in
            var down = 0.0, up = 0.0
            for pid in rows.keys where identity(pid).id == entry.id {
                down += received[pid] ?? 0
                up += sent[pid] ?? 0
            }
            return (entry, down, up)
        }
    }

    private func startGPU() {
        guard gpuTimer == nil else { return }
        let timer = Timer(timeInterval: 3, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.sampleGPU() } }
        RunLoop.main.add(timer, forMode: .common)
        gpuTimer = timer
        sampleGPU()
    }

    private func sampleGPU() {
        Task { [weak self] in
            let (times, now) = await Self.readGPUTimes()
            guard let self else { return }
            defer { self.lastGPU = (times, now) }
            guard let last = self.lastGPU else { return }
            // Nanoseconds of GPU time per second of wall time, as a percentage of one GPU.
            let rates = CounterRates.rates(before: last.times, after: times, seconds: now - last.at).mapValues { $0 / 1e9 * 100 }
            self.gpu = UsageRanking.top(rates.map { ($0.key, $0.value) }, limit: 5, identity: self.identities.resolver(commands: [:]))
        }
    }

    nonisolated private static func readGPUTimes() async -> ([Int32: UInt64], TimeInterval) {
        (GPUReader.timeByProcess(), ProcessInfo.processInfo.systemUptime)
    }
}

/// Names a process the way a person would recognize it: the app it belongs to, or its own name.
@MainActor final class ProcessIdentities {
    private var cache: [Int32: (path: String?, id: String, name: String)] = [:]

    func resolver(commands: [Int32: String]) -> (Int32) -> (id: String, name: String, path: String?) {
        { [self] pid in
            if let known = cache[pid] { return (known.id, known.name, known.path) }
            let executable = ProcessPath.executable(of: pid)
            let found: (path: String?, id: String, name: String)
            if let executable, let bundle = AppGrouping.appBundle(forExecutable: executable) {
                found = (bundle, bundle, FileManager.default.displayName(atPath: bundle).replacingOccurrences(of: ".app", with: ""))
            } else {
                let name = executable.map { ($0 as NSString).lastPathComponent } ?? commands[pid] ?? "pid \(pid)"
                found = (executable, "pid:\(pid)", pid == 0 ? String(localized: "macOS kernel") : name)
            }
            cache[pid] = found
            if cache.count > 4_000 { cache.removeAll() }
            return (found.id, found.name, found.path)
        }
    }
}

/// Where a running process's executable is.
enum ProcessPath {
    static func executable(of pid: Int32) -> String? {
        var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        return proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 ? String(cString: buffer) : nil
    }
}

/// A command-line tool that keeps printing, read line by line until stopped.
final class StreamingTool: @unchecked Sendable {
    private let process = Process()
    private var buffer = Data()

    init(path: String, arguments: [String], onLine: @escaping (String) -> Void) {
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard let self, !data.isEmpty else {
                handle.readabilityHandler = nil
                return
            }
            self.buffer.append(data)
            while let newline = self.buffer.firstIndex(of: 0x0A) {
                let line = String(decoding: self.buffer[self.buffer.startIndex..<newline], as: UTF8.self)
                self.buffer.removeSubrange(self.buffer.startIndex...newline)
                onLine(line)
            }
        }
        try? process.run()
    }

    func stop() {
        if process.isRunning { process.terminate() }
    }

    deinit { stop() }
}
