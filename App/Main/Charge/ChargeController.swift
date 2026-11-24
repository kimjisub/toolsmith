import Foundation
import Security
import ServiceManagement
import ToolsmithKit

/// The app's side of battery charge control. Where macOS has a charge limit of its own (26.4 and
/// later on Apple silicon) that is what it drives: the firmware keeps it even asleep, and nothing
/// needs installing. Elsewhere it installs the administrator helper (a launchd daemon registered
/// with SMAppService) and talks to it over XPC.
///
/// Both follow `ChargePlanner`: below the limit the battery charges, at or above it it is held on
/// the adapter, and it runs down only when the user asks to discharge. macOS's limit runs a battery
/// above it down to it, so while holding above the user's limit, macOS is given the battery's own
/// level (`SystemChargeMemory`) and the user's limit is kept by the app.
@MainActor final class ChargeController: ObservableObject {
    enum State: Equatable {
        /// macOS's own charge limit is in charge.
        case system
        /// This build cannot install the helper (not signed with the team's Developer ID).
        case unsupportedBuild
        /// No battery on this Mac.
        case noBattery
        case notInstalled
        /// Registered, waiting for the user to allow it in System Settings → General → Login Items.
        case needsApproval
        case running
        /// The helper runs but is older than this app (its version); it needs updating.
        case outdated(Int)
        /// The helper runs but this Mac's controller offers no key it knows.
        case unsupportedMac
        case failed(String)
    }

    @Published private(set) var state: State = .notInstalled
    @Published private(set) var status: ChargeStatus?
    @Published private(set) var busy = false
    @Published private(set) var system: SystemChargeLimitState?
    @Published private(set) var systemError: String?
    /// What the screens show; nil until something controls the charge.
    @Published private(set) var snapshot: ChargeSnapshot?

    private let systemClient = SystemChargeLimitClient()
    private let service = SMAppService.daemon(plistName: ChargeHelperIdentity.plistName)
    private var connection: NSXPCConnection?
    private var memoryDocument = JSONDocument<SystemChargeMemory>(fileURL: SettingsStore.supportDirectory
        .appendingPathComponent("charge", isDirectory: true).appendingPathComponent("system-limit.json"))
    private var memory = SystemChargeMemory()
    private var timer: Timer?
    #if TOOLSMITH_DEV
    /// A made-up state for pictures: nothing is read from or written to the Mac while it is set.
    private var demo: ChargeSnapshot?
    private var isDemo: Bool { demo != nil }
    #else
    private let isDemo = false
    #endif

    init() {
        memory = memoryDocument.load() ?? SystemChargeMemory()
        #if TOOLSMITH_DEV
        // Set before anything is read, so a development build drawing pictures never writes a limit.
        if let made = ChargeModule.demoSnapshot(CommandLine.arguments) {
            demo = made
            snapshot = made
            state = .system
        }
        #endif
    }

    /// Follows the battery while the module runs: the hold target trails the level, a discharge ends
    /// at the limit. macOS's limit and the helper keep the charge on their own in between.
    func start() {
        refresh()
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 30, repeats: true) { [weak self] _ in Task { @MainActor in self?.refresh() } }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        connection?.invalidate()
        connection = nil
    }

    /// Looks again at the helper's registration and, when it runs, at its report; with macOS's limit,
    /// makes and applies the plan.
    func refresh() {
        guard !isDemo else { return }
        guard BatteryReader.battery() != nil else { state = .noBattery; snapshot = nil; return }
        if let systemClient {
            // A failed read keeps the last value rather than falling back to a helper this Mac does not need.
            if let read = systemClient.read() { system = read }
            if system != nil {
                state = .system
                releaseLeftoverHelper()
                applySystemPlan()
                return
            }
        }
        guard Self.isSignedByTeam else { state = .unsupportedBuild; return }
        switch service.status {
        case .notRegistered, .notFound: state = .notInstalled
        case .requiresApproval: state = .needsApproval
        case .enabled: call { $0.status(reply: $1) }
        @unknown default: state = .notInstalled
        }
    }

    /// A helper installed before this Mac had its own limit would go on holding its old limit:
    /// tell it once to give charging back.
    private func releaseLeftoverHelper() {
        guard !releasedHelper, service.status == .enabled else { return }
        releasedHelper = true
        call { $0.restoreDefaults(reply: $1) }
    }

    private var releasedHelper = false

    func install() {
        guard Self.isSignedByTeam else { state = .unsupportedBuild; return }
        do {
            try service.register()
        } catch {
            // Registering an approved-but-pending item reports an error; the status says what to do.
            if service.status != .requiresApproval { state = .failed(String(localized: "Couldn’t install the helper: \(error.localizedDescription)")) }
        }
        refresh()
        if state == .needsApproval { SMAppService.openSystemSettingsLoginItems() }
    }

    /// Gives charging back, then removes the helper.
    func uninstall() {
        busy = true
        let finish: @MainActor () -> Void = { [weak self] in
            guard let self else { return }
            self.connection?.invalidate()
            self.connection = nil
            do {
                try self.service.unregister()
            } catch {
                self.state = .failed(String(localized: "Couldn’t remove the helper: \(error.localizedDescription)"))
            }
            self.status = nil
            self.busy = false
            self.refresh()
        }
        // A helper left over on a Mac that now uses macOS's own limit still gives charging back first.
        if service.status == .enabled { call({ $0.restoreDefaults(reply: $1) }, then: finish) } else { finish() }
    }

    /// Replaces a running helper older than this app. Unregistering stops it (it gives charging back
    /// as it exits); registering again starts the copy inside this app. The approval in Login Items
    /// stays, since the helper's identity does not change.
    func updateHelper() {
        guard Self.isSignedByTeam else { state = .unsupportedBuild; return }
        busy = true
        connection?.invalidate()
        connection = nil
        Task { @MainActor in
            do {
                try await service.unregister()
                try service.register()
            } catch {
                if service.status != .requiresApproval { state = .failed(String(localized: "Couldn’t update the helper: \(error.localizedDescription)")) }
            }
            status = nil
            busy = false
            refresh()
        }
    }

    func openLoginItems() { SMAppService.openSystemSettingsLoginItems() }

    /// Whether a helper from before is still registered (on a Mac that no longer needs it).
    var helperRegistered: Bool { service.status == .enabled || service.status == .requiresApproval }

    // MARK: What the controls show, whichever does the work

    /// The limits the user can pick; 100 stands for none.
    var choices: [Int] {
        if state == .system { return system?.choices ?? SystemChargeLimitState.fallbackChoices }
        return [50, 60, 70, 80, 85, 90, 95, 100]
    }

    var canControl: Bool { isDemo || state == .system || state == .running }

    var error: String? { state == .system ? systemError : status?.error }

    func setLimit(_ percent: Int?) {
        guard !isDemo else { return }
        if state == .system {
            memory.limit = percent.flatMap { $0 >= 100 ? nil : $0 }
            applySystemPlan()
        } else {
            call { $0.setLimit(percent ?? 0, reply: $1) }
        }
    }

    /// Runs the battery down to the limit while plugged in; ends there by itself.
    func setDischarging(_ on: Bool) {
        guard !isDemo else { return }
        if state == .system {
            if on, system?.mode == .toppingUp { systemError = systemClient?.resume() }
            memory.discharging = on
            readSystem()
            applySystemPlan()
        } else {
            call { $0.setDischarging(on, reply: $1) }
        }
    }

    /// Charges to full this once; the limit comes back when it is full or unplugged.
    func setToppingUp(_ on: Bool) {
        guard !isDemo else { return }
        if state == .system {
            guard let systemClient else { return }
            memory.discharging = false
            systemError = on ? systemClient.topUp() : systemClient.resume()
            readSystem()
            applySystemPlan()
        } else {
            call { $0.setTopUp(on, reply: $1) }
        }
    }

    // MARK: macOS's own limit

    private func readSystem() {
        system = systemClient?.read() ?? system
    }

    /// Plans from the battery and macOS's limit as they are, writes macOS's limit if the plan needs
    /// another value, and keeps what the app must remember.
    private func applySystemPlan() {
        guard let systemClient, let current = system, let battery = BatteryReader.battery() else { return }
        let before = memory
        memory = memory.reconciled(with: current)
        let plan = ChargePlanner.plan(memory.input(level: battery.level, onAdapter: battery.onAdapter, state: current))
        memory.discharging = plan.request == .discharge
        memory.holding = plan.holding
        if let value = SystemChargeMemory.write(for: plan, state: current) {
            let failure = systemClient.set(limit: value)
            systemError = failure
            if failure == nil { memory.written = value }
            readSystem()
        }
        if memory != before { memoryDocument.save(memory) }
        snapshot = ChargeSnapshot(activity: plan.activity, level: battery.level, onAdapter: battery.onAdapter, limit: memory.limit,
                                  abilities: .system, batteryWatts: BatteryReader.batteryWatts())
    }

    // MARK: The helper

    private func helperReported(_ status: ChargeStatus?) {
        self.status = status
        guard let status, state != .system else { return }
        if status.version < ChargeHelperIdentity.version {
            state = .outdated(status.version)
            snapshot = nil
            return
        }
        state = status.canPause || status.canDischarge ? .running : .unsupportedMac
        let battery = BatteryReader.battery()
        let activity = status.activity ?? (battery?.onAdapter == true ? .charging : .onBattery)
        snapshot = state == .running
            ? ChargeSnapshot(activity: activity, level: battery?.level ?? status.level, onAdapter: battery?.onAdapter ?? false,
                             limit: status.settings.limit, abilities: status.abilities, batteryWatts: BatteryReader.batteryWatts())
            : nil
    }

    private func call(_ send: @escaping (ChargeHelperProtocol, @escaping (Data) -> Void) -> Void, then done: (@MainActor () -> Void)? = nil) {
        let connection = self.connection ?? makeConnection()
        let proxy = connection.remoteObjectProxyWithErrorHandler { [weak self] error in
            Task { @MainActor in
                self?.connection = nil
                self?.state = .failed(String(localized: "Couldn’t connect to the helper: \(error.localizedDescription)"))
                self?.snapshot = nil
                done?()
            }
        }
        guard let helper = proxy as? ChargeHelperProtocol else { return }
        send(helper) { [weak self] data in
            let status = try? JSONDecoder().decode(ChargeStatus.self, from: data)
            Task { @MainActor in
                self?.helperReported(status)
                done?()
            }
        }
    }

    private func makeConnection() -> NSXPCConnection {
        let connection = NSXPCConnection(machServiceName: ChargeHelperIdentity.machService, options: .privileged)
        connection.remoteObjectInterface = NSXPCInterface(with: ChargeHelperProtocol.self)
        // Talk only to our own helper, signed by our team.
        connection.setCodeSigningRequirement(ChargeHelperIdentity.requirement(identifier: ChargeHelperIdentity.helperBundleID))
        connection.invalidationHandler = { [weak self] in Task { @MainActor in self?.connection = nil } }
        connection.resume()
        self.connection = connection
        return connection
    }

    /// Whether this copy of the app carries the team's Developer ID signature. The helper only
    /// accepts such an app, and only such an app can register it.
    static var isSignedByTeam: Bool { CodeSignature.isSignedByTeam }
}
