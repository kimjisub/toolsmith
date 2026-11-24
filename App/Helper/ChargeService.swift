import Foundation
import IOKit.ps
import IOKit.pwr_mgt
import ToolsmithKit

/// Keeps the battery where the user asked: stops charging at the limit (or runs from the battery
/// when the Mac cannot stop charging), pauses on request, and gives everything back on the way out.
/// All work happens on the main queue.
final class ChargeService: NSObject, ChargeHelperProtocol {
    private let smc = SMC()
    private let keys: ChargeKeys
    private var settings: ChargeSettings
    private var output = ChargeOutput.normal
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
        settings = Self.loadSettings()
        super.init()
    }

    private var sleeping = false

    func start() {
        // After a restart the controller may hold an older state: write all of it once.
        apply(force: true)
        // Every minute, and whenever the power source or level changes.
        let timer = Timer(timeInterval: 60, repeats: true) { [weak self] _ in self?.apply() }
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
    /// writes everything again on waking.
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
            write(ChargeDecision.forSleep(output), force: false)
            IOAllowPowerChange(rootPort, token)
        case PowerMessage.systemHasPoweredOn:
            sleeping = false
            apply(force: true)
        default:
            break
        }
    }

    /// Charging on, adapter on. Called before the helper exits.
    func giveBack() {
        write(.normal, force: true)
    }

    // MARK: XPC (calls arrive on a connection queue; work hops to main)

    func status(reply: @escaping (Data) -> Void) {
        DispatchQueue.main.async { reply(self.report()) }
    }

    func setLimit(_ percent: Int, reply: @escaping (Data) -> Void) {
        DispatchQueue.main.async {
            self.settings.limit = ChargeLimit.clamp(percent)
            self.saveAndApply()
            reply(self.report())
        }
    }

    func setPaused(_ paused: Bool, reply: @escaping (Data) -> Void) {
        DispatchQueue.main.async {
            self.settings.paused = paused && self.keys.canPause
            self.saveAndApply()
            reply(self.report())
        }
    }

    func setDischarging(_ discharging: Bool, reply: @escaping (Data) -> Void) {
        DispatchQueue.main.async {
            self.settings.discharging = discharging && self.keys.canDischarge
            self.saveAndApply()
            reply(self.report())
        }
    }

    func restoreDefaults(reply: @escaping (Data) -> Void) {
        DispatchQueue.main.async {
            self.settings = .defaults
            self.saveAndApply()
            reply(self.report())
        }
    }

    // MARK: Work

    private func saveAndApply() {
        Self.save(settings)
        apply()
    }

    private func apply(force: Bool = false) {
        // Between the sleep notice and the sleep itself the adapter stays as it was put.
        guard !sleeping else { return }
        let level = Self.level() ?? .nan
        if settings.discharging, ChargeDecision.dischargeDone(level: level, settings: settings) {
            settings.discharging = false
            Self.save(settings)
        }
        let next = ChargeDecision.decide(level: level, settings: settings, keys: keys, current: output)
        write(next, force: force)
    }

    /// Writes what changed (everything when forced), and only keys this Mac has.
    private func write(_ next: ChargeOutput, force: Bool) {
        guard let smc else {
            lastError = "SMC 를 열 수 없습니다"
            return
        }
        var failed: [String] = []
        if force || next.inhibit != output.inhibit {
            for write in keys.inhibit where !smc.writeBytes(write.key, next.inhibit ? write.on : write.off) { failed.append(write.key) }
        }
        if let adapter = keys.adapter, force || next.adapterOff != output.adapterOff {
            if !smc.writeBytes(adapter.key, next.adapterOff ? adapter.on : adapter.off) { failed.append(adapter.key) }
        }
        lastError = failed.isEmpty ? nil : "SMC 가 \(failed.joined(separator: ", ")) 쓰기를 거절했습니다"
        if failed.isEmpty { output = next }
    }

    private func report() -> Data {
        let status = ChargeStatus(settings: settings, output: output, canPause: keys.canPause, canDischarge: keys.canDischarge,
                                  level: Self.level(), error: lastError)
        return (try? JSONEncoder().encode(status)) ?? Data()
    }

    /// The internal battery's level (0…100), or nil.
    private static func level() -> Double? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for source in list {
            guard let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                  let current = description[kIOPSCurrentCapacityKey] as? Int, let maximum = description[kIOPSMaxCapacityKey] as? Int,
                  maximum > 0 else { continue }
            return Double(current) / Double(maximum) * 100
        }
        return nil
    }

    private static func loadSettings() -> ChargeSettings {
        guard let data = try? Data(contentsOf: stateFile), let settings = try? JSONDecoder().decode(ChargeSettings.self, from: data) else { return .defaults }
        return ChargeSettings(limit: settings.limit, paused: settings.paused, discharging: settings.discharging)
    }

    private static func save(_ settings: ChargeSettings) {
        let manager = FileManager.default
        try? manager.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        guard let data = try? JSONEncoder().encode(settings) else { return }
        try? data.write(to: stateFile, options: .atomic)
        try? manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: stateFile.path)
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
