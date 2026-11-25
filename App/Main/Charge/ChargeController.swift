import Foundation
import Security
import ServiceManagement
import ToolsmithKit

/// The app's side of battery charge control. The administrator helper (a launchd daemon registered
/// with SMAppService) does the work, by AlDente's rules, whether the Mac still has the charge
/// controller's keys or only macOS's own limit; the app installs it, talks to it over XPC and shows
/// what it reports. macOS's limit alone cannot hold a battery above it (it runs the battery down to
/// it) nor take values outside its list, which is why the helper is needed on every Mac.
@MainActor final class ChargeController: ObservableObject {
    enum State: Equatable {
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
        /// The helper runs but finds no way to control charging on this Mac.
        case unsupportedMac
        case failed(String)
    }

    @Published private(set) var state: State = .notInstalled
    @Published private(set) var status: ChargeStatus?
    @Published private(set) var busy = false
    /// What the screens show; nil until the helper reports.
    @Published private(set) var snapshot: ChargeSnapshot?

    private let service = SMAppService.daemon(plistName: ChargeHelperIdentity.plistName)
    private var connection: NSXPCConnection?
    private var timer: Timer?
    #if TOOLSMITH_DEV
    /// A made-up state for pictures: nothing is read from or sent to the helper while it is set.
    private var demo: ChargeSnapshot?
    private var isDemo: Bool { demo != nil }
    #else
    private let isDemo = false
    #endif

    init() {
        #if TOOLSMITH_DEV
        if let made = ChargeModule.demoSnapshot(CommandLine.arguments) {
            demo = made
            snapshot = made
            state = .running
        }
        #endif
    }

    /// Asks the helper how things are while the module runs. The helper keeps the charge on its own.
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

    /// Looks again at the helper's registration and, when it runs, at its report.
    func refresh() {
        guard !isDemo else { return }
        guard BatteryReader.battery() != nil else { state = .noBattery; snapshot = nil; return }
        guard Self.isSignedByTeam else { state = .unsupportedBuild; return }
        switch service.status {
        case .notRegistered, .notFound: state = .notInstalled
        case .requiresApproval: state = .needsApproval
        case .enabled: call { $0.status(reply: $1) }
        @unknown default: state = .notInstalled
        }
    }

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

    /// Gives charging back (and macOS's limit as it was), then removes the helper.
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
            self.snapshot = nil
            self.busy = false
            self.refresh()
        }
        if service.status == .enabled { call({ $0.restoreDefaults(reply: $1) }, then: finish) } else { finish() }
    }

    /// Replaces a running helper older than this app. Unregistering stops it (it gives charging back
    /// as it exits); registering again starts the copy inside this app.
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

    // MARK: What the controls show

    var choices: [Int] { ChargeLimit.choices }
    var canControl: Bool { isDemo || state == .running }
    var error: String? { status?.error }

    func setLimit(_ percent: Int?) {
        guard !isDemo else { return }
        call { $0.setLimit(percent ?? 0, reply: $1) }
    }

    func setSailing(_ points: Int) {
        guard !isDemo else { return }
        call { $0.setSailing(points, reply: $1) }
    }

    /// Runs the battery down to the limit while plugged in; ends there by itself.
    func setDischarging(_ on: Bool) {
        guard !isDemo else { return }
        call { $0.setDischarging(on, reply: $1) }
    }

    /// Charges to 100% and keeps it there until unplugged.
    func setToppingUp(_ on: Bool) {
        guard !isDemo else { return }
        call { $0.setTopUp(on, reply: $1) }
    }

    // MARK: The helper

    private func helperReported(_ status: ChargeStatus?) {
        self.status = status
        guard let status else { return }
        if status.version < ChargeHelperIdentity.version {
            state = .outdated(status.version)
            snapshot = nil
            return
        }
        state = status.canPause || status.canDischarge || status.method == .nativeLimit ? .running : .unsupportedMac
        let battery = BatteryReader.battery()
        let activity = status.activity ?? (battery?.onAdapter == true ? .charging : .onBattery)
        snapshot = state == .running
            ? ChargeSnapshot(activity: activity, level: battery?.level ?? status.level, onAdapter: battery?.onAdapter ?? false,
                             limit: status.settings.limit, sailing: status.settings.sailing, abilities: status.abilities,
                             batteryWatts: BatteryReader.batteryWatts(), conflicts: status.conflicts ?? [])
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
