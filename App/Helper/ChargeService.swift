import Foundation
import IOKit.ps
import IOKit.pwr_mgt
import ToolsmithKit

/// Keeps the battery where the user asked, by AlDente's rules (`ChargePlanner`): charges to the
/// limit, sails on the adapter until the battery falls the sailing range below it, pauses at the
/// level when the limit is under it, runs from the battery only when asked to discharge, and charges
/// to 100% on request until unplugged. It drives the charge controller's keys where the firmware
/// still has them, and macOS's own limit set to any percentage where it does not. While another
/// charge app runs it writes nothing. All work happens on the main queue.
final class ChargeService: NSObject, ChargeHelperProtocol {
    private let smc = SMC()
    private let keys: ChargeKeys
    private let native: NativeLimitWriter?
    private let method: ChargeMethod
    private var settings: ChargeSettings
    private var output = ChargeOutput.normal
    private var activity = ChargeActivity.charging
    private var charging = false
    private var watch = NativeLimitWatch()
    private var target: Int?
    private var conflicts: [String] = []
    private var lastError: String?
    private var timer: Timer?
    private var powerPort: IONotificationPortRef?
    private var rootPort: io_connect_t = 0
    private var powerNotifier: io_object_t = 0

    /// Root-only: the folder is 0700 and the file 0600.
    private static let folder = URL(fileURLWithPath: "/Library/Application Support/\(ChargeHelperIdentity.helperBundleID)", isDirectory: true)
    private static var stateFile: URL { folder.appendingPathComponent("settings.json") }

    override init() {
        var present: Set<String> = []
        if let smc { present = ChargeKeys.candidates.filter(smc.has) }
        keys = ChargeKeys(present: present)
        try? FileManager.default.createDirectory(at: Self.folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        // The keys first: they act at once and need nothing of macOS. macOS's limit where they are gone.
        native = keys.canPause ? nil : NativeLimitWriter(folder: Self.folder)
        method = keys.canPause ? .keys : native != nil ? .nativeLimit : .none
        settings = Self.loadSettings()
        super.init()
    }

    private var abilities: ChargeAbilities {
        switch method {
        case .keys: return ChargeAbilities(canHold: true, canDischarge: keys.canDischarge)
        case .nativeLimit: return ChargeAbilities(canHold: !watch.failed, canDischarge: !watch.failed)
        case .none: return ChargeAbilities(canHold: false, canDischarge: keys.canDischarge)
        }
    }

    private var sleeping = false

    func start() {
        // After a restart the controller may hold an older state: write all of it once.
        apply(force: true)
        // Every half minute (another charge app may have quit and left a limit behind), and whenever
        // the power source or level changes.
        let timer = Timer(timeInterval: 30, repeats: true) { [weak self] _ in self?.apply() }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        let context = Unmanaged.passUnretained(self).toOpaque()
        if let source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            Unmanaged<ChargeService>.fromOpaque(context).takeUnretainedValue().apply()
        }, context)?.takeRetainedValue() {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
        }
        watchSleep()
    }

    /// Puts the adapter back before the Mac sleeps (nothing watches the level while it does) and
    /// writes everything again on waking. macOS's own limit is kept by the firmware asleep.
    private func watchSleep() {
        let context = Unmanaged.passUnretained(self).toOpaque()
        rootPort = IORegisterForSystemPower(context, &powerPort, { context, _, message, argument in
            guard let context else { return }
            let service = Unmanaged<ChargeService>.fromOpaque(context).takeUnretainedValue()
            service.powerChanged(message: message, argument: argument)
        }, &powerNotifier)
        if let powerPort, rootPort != 0 {
            CFRunLoopAddSource(CFRunLoopGetMain(), IONotificationPortGetRunLoopSource(powerPort).takeUnretainedValue(), .defaultMode)
        }
    }

    /// IOKit's power messages (`iokit_common_msg(0x270)` and so on); the C macros do not reach Swift.
    private enum PowerMessage {
        static let canSystemSleep: natural_t = 0xE000_0270
        static let systemWillSleep: natural_t = 0xE000_0280
        static let systemHasPoweredOn: natural_t = 0xE000_0300
    }

    private func powerChanged(message: natural_t, argument: UnsafeMutableRawPointer?) {
        let token = Int(bitPattern: argument)
        switch message {
        case PowerMessage.canSystemSleep:
            IOAllowPowerChange(rootPort, token)
        case PowerMessage.systemWillSleep:
            sleeping = true
            if method == .keys, conflicts.isEmpty { writeKeys(ChargePlanner.forSleep(output), force: false) }
            IOAllowPowerChange(rootPort, token)
        case PowerMessage.systemHasPoweredOn:
            sleeping = false
            apply(force: true)
        default:
            break
        }
    }

    /// Charging on, adapter on, macOS's limit as the user had it. Called before the helper exits.
    func giveBack() {
        guard conflicts.isEmpty else { return }
        if method == .keys || keys.canDischarge { writeKeys(.normal, force: true) }
        if let failure = native?.giveBack() { lastError = failure }
        target = nil
    }

    // MARK: XPC (calls arrive on a connection queue; work hops to main)

    func status(reply: @escaping (Data) -> Void) {
        DispatchQueue.main.async { reply(self.report()) }
    }

    func setLimit(_ percent: Int, reply: @escaping (Data) -> Void) {
        change(reply) { $0.limit = ChargeLimit.clamp(percent) }
    }

    func setSailing(_ points: Int, reply: @escaping (Data) -> Void) {
        change(reply) { $0.sailing = ChargeLimit.clampSailing(points) }
    }

    func setDischarging(_ discharging: Bool, reply: @escaping (Data) -> Void) {
        change(reply) { $0.request = discharging ? .discharge : .none }
    }

    func setTopUp(_ toppingUp: Bool, reply: @escaping (Data) -> Void) {
        change(reply) { $0.request = toppingUp ? .topUp : .none }
    }

    func restoreDefaults(reply: @escaping (Data) -> Void) {
        DispatchQueue.main.async {
            self.settings = .defaults
            Self.save(self.settings)
            self.giveBack()
            reply(self.report())
        }
    }

    private func change(_ reply: @escaping (Data) -> Void, _ edit: @escaping (inout ChargeSettings) -> Void) {
        DispatchQueue.main.async {
            edit(&self.settings)
            Self.save(self.settings)
            self.apply()
            reply(self.report())
        }
    }

    // MARK: Work

    private func apply(force: Bool = false) {
        // Between the sleep notice and the sleep itself everything stays as it was put.
        guard !sleeping else { return }
        conflicts = ChargeConflicts.detect(RunningProcesses.descriptions())
        let battery = Self.battery()
        let plan = ChargePlanner.plan(ChargeInput(level: battery?.level ?? .nan, onAdapter: battery?.onAdapter ?? false,
                                                  limit: settings.limit, sailing: settings.sailing, request: settings.request,
                                                  abilities: abilities, wasCharging: charging))
        activity = plan.activity
        // Another app is in charge: leave the controller and macOS's limit as it set them.
        guard conflicts.isEmpty else { return }
        if plan.request != settings.request {
            settings.request = plan.request
            Self.save(settings)
        }
        charging = plan.charging
        switch method {
        case .keys:
            writeKeys(plan.output, force: force)
        case .nativeLimit:
            writeNative(plan)
        case .none:
            writeKeys(ChargeOutput(inhibit: false, adapterOff: plan.output.adapterOff), force: force)
        }
    }

    /// macOS's limit: the plan's target, once per change, checked against what macOS reports. With no
    /// limit and nothing asked, the user's own setting goes back.
    private func writeNative(_ plan: ChargePlan) {
        guard let native else { return }
        if settings.limit == nil, plan.request == .none {
            if let failure = native.giveBack() { lastError = failure }
            target = nil
            return
        }
        let now = Date()
        let reported = native.reported()
        watch.observe(reported, now: now)
        if watch.failed {
            lastError = "macOS did not take the charge limit \(watch.written.map(String.init) ?? "")%"
            return
        }
        guard watch.shouldWrite(plan.target, reported: reported, now: now) else { return }
        if native.write(plan.target) {
            watch.wrote(plan.target, at: now)
            target = plan.target
            lastError = nil
        } else {
            lastError = "Couldn’t save macOS’s charge limit"
        }
    }

    /// Writes what changed (everything when forced), and only keys this Mac has.
    private func writeKeys(_ next: ChargeOutput, force: Bool) {
        guard let smc else {
            lastError = "Cannot open the SMC"
            return
        }
        var failed: [String] = []
        if force || next.inhibit != output.inhibit {
            for write in keys.inhibit where !smc.writeBytes(write.key, next.inhibit ? write.on : write.off) { failed.append(write.key) }
        }
        if let adapter = keys.adapter, force || next.adapterOff != output.adapterOff {
            if !smc.writeBytes(adapter.key, next.adapterOff ? adapter.on : adapter.off) { failed.append(adapter.key) }
        }
        lastError = failed.isEmpty ? nil : "The SMC refused to write \(failed.joined(separator: ", "))"
        if failed.isEmpty { output = next }
    }

    private func report() -> Data {
        let abilities = self.abilities
        let status = ChargeStatus(settings: settings, output: output, canPause: abilities.canHold, canDischarge: abilities.canDischarge,
                                  level: Self.battery()?.level, error: lastError, activity: activity, method: method,
                                  target: target, systemLimit: native?.reported(), conflicts: conflicts)
        return (try? JSONEncoder().encode(status)) ?? Data()
    }

    /// The internal battery's level (0…100) and whether the adapter powers the Mac, or nil.
    private static func battery() -> (level: Double, onAdapter: Bool)? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for source in list {
            guard let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                  let current = description[kIOPSCurrentCapacityKey] as? Int, let maximum = description[kIOPSMaxCapacityKey] as? Int,
                  maximum > 0 else { continue }
            return (Double(current) / Double(maximum) * 100, description[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue)
        }
        return nil
    }

    private static func loadSettings() -> ChargeSettings {
        guard let data = try? Data(contentsOf: stateFile), let settings = try? JSONDecoder().decode(ChargeSettings.self, from: data) else { return .defaults }
        return settings
    }

    private static func save(_ settings: ChargeSettings) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        try? data.write(to: stateFile, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: stateFile.path)
    }
}

/// Accepts connections (already checked against the app's signature by the listener) and serves
/// the charge vocabulary on them.
final class ListenerDelegate: NSObject, NSXPCListenerDelegate {
    private let service: ChargeService
    init(service: ChargeService) { self.service = service }

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        connection.exportedInterface = NSXPCInterface(with: ChargeHelperProtocol.self)
        connection.exportedObject = service
        connection.resume()
        return true
    }
}

/// Signal sources live as long as the process.
var signalSources: [DispatchSourceSignal] = []
