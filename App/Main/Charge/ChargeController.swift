import Foundation
import Security
import ServiceManagement
import ToolsmithKit

/// The app's side of battery charge control. Where macOS has a charge limit of its own (26.4 and
/// later on Apple silicon) that is what it drives: the firmware keeps it even asleep, and nothing
/// needs installing. Elsewhere it installs the administrator helper (a launchd daemon registered
/// with SMAppService) and talks to it over XPC.
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
        /// The helper runs but this Mac's controller offers no key it knows.
        case unsupportedMac
        case failed(String)
    }

    @Published private(set) var state: State = .notInstalled
    @Published private(set) var status: ChargeStatus?
    @Published private(set) var busy = false
    @Published private(set) var system: SystemChargeLimitState?
    @Published private(set) var systemError: String?

    private let systemClient = SystemChargeLimitClient()
    private let service = SMAppService.daemon(plistName: ChargeHelperIdentity.plistName)
    private var connection: NSXPCConnection?

    init() { refresh() }

    /// Looks again at the helper's registration and, when it runs, at its report.
    func refresh() {
        guard BatteryReader.battery() != nil else { state = .noBattery; return }
        if let systemClient {
            // A failed read keeps the last value rather than falling back to a helper this Mac does not need.
            if let read = systemClient.read() { system = read }
            if system != nil {
                state = .system
                releaseLeftoverHelper()
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
            if service.status != .requiresApproval { state = .failed("도우미를 설치하지 못했습니다: \(error.localizedDescription)") }
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
                self.state = .failed("도우미를 지우지 못했습니다: \(error.localizedDescription)")
            }
            self.status = nil
            self.busy = false
            self.refresh()
        }
        // A helper left over on a Mac that now uses macOS's own limit still gives charging back first.
        if service.status == .enabled { call({ $0.restoreDefaults(reply: $1) }, then: finish) } else { finish() }
    }

    func openLoginItems() { SMAppService.openSystemSettingsLoginItems() }

    /// Whether a helper from before is still registered (on a Mac that no longer needs it).
    var helperRegistered: Bool { service.status == .enabled || service.status == .requiresApproval }

    // MARK: What the controls show, whichever does the work

    /// The limit in effect, or nil when the battery charges to full.
    var limit: Int? {
        if state == .system { return system?.effectiveLimit }
        return status?.settings.limit
    }

    /// The limits the user can pick; 100 stands for none.
    var choices: [Int] {
        if state == .system { return system?.choices ?? SystemChargeLimitState.fallbackChoices }
        return [50, 60, 70, 80, 85, 90, 95, 100]
    }

    var canControl: Bool { state == .system || state == .running }
    var canTopUp: Bool { state == .system }
    var toppingUp: Bool { system?.mode == .toppingUp }
    var canPause: Bool { state == .running && status?.canPause == true }
    var canDischarge: Bool { state == .running && status?.canDischarge == true }
    var paused: Bool { status?.settings.paused ?? false }
    var discharging: Bool { status?.settings.discharging ?? false }
    var error: String? { state == .system ? systemError : status?.error }

    func setLimit(_ percent: Int?) {
        if state == .system {
            updateSystem { $0.set(limit: percent ?? 100) }
        } else {
            call { $0.setLimit(percent ?? 0, reply: $1) }
        }
    }

    /// Charges to full this once; the limit comes back when it is full or unplugged.
    func topUp() { updateSystem { $0.topUp() } }
    func resumeLimit() { updateSystem { $0.resume() } }

    private func updateSystem(_ change: (SystemChargeLimitClient) -> String?) {
        guard let systemClient else { return }
        systemError = change(systemClient)
        system = systemClient.read() ?? system
    }

    func setPaused(_ paused: Bool) { call { $0.setPaused(paused, reply: $1) } }
    func setDischarging(_ discharging: Bool) { call { $0.setDischarging(discharging, reply: $1) } }

    // MARK: XPC

    private func call(_ send: @escaping (ChargeHelperProtocol, @escaping (Data) -> Void) -> Void, then done: (@MainActor () -> Void)? = nil) {
        let connection = self.connection ?? makeConnection()
        let proxy = connection.remoteObjectProxyWithErrorHandler { [weak self] error in
            Task { @MainActor in
                self?.connection = nil
                self?.state = .failed("도우미에 연결하지 못했습니다: \(error.localizedDescription)")
                done?()
            }
        }
        guard let helper = proxy as? ChargeHelperProtocol else { return }
        send(helper) { [weak self] data in
            let status = try? JSONDecoder().decode(ChargeStatus.self, from: data)
            Task { @MainActor in
                guard let self else { return }
                self.status = status
                if let status, self.state != .system {
                    self.state = status.canPause || status.canDischarge ? .running : .unsupportedMac
                }
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
