import AppKit
import Combine
import CoreAudio
import ToolsmithKit

/// One system device line: the device chosen for the role and what can be done with it.
struct SystemDeviceState: Equatable {
    var device: AudioDevice?
    var volume: Double?
    var canSetVolume = false
    var muted: Bool?
    var canMute = false
    var balance: Double?
    var canSetBalance = false
    var sampleRate: Double?
    var sampleRates: [Double] = []
}

/// One line of the app list, ready to draw.
struct MixerAppRow: Identifiable, Equatable {
    let key: String
    let name: String
    /// The app bundle, for the icon.
    let appPath: String?
    let row: AudioAppRow
    let settings: AppAudioSettings
    /// The device or group the app was sent to, when none of it is connected now (it plays on the system output meanwhile).
    let outputMissing: Bool
    let routeError: String?
    let timedMuteUntil: Date?
    var id: String { key }
}

/// The levels the meters show, apart from the mixer so only the meters redraw fifteen times a second.
@MainActor final class MeterLevels: ObservableObject {
    @Published private(set) var levels: [String: Float] = [:]

    func set(_ next: [String: Float]) {
        if next != levels { levels = next }
    }

    func level(_ key: String) -> Float { levels[key] ?? 0 }
}

/// The mixer: reads the system's devices and the apps playing sound, keeps one route running per
/// app the user changed (and one for the system output's effects), meters while on screen, and
/// saves the settings. State lives on the main thread; routes are built on the engine's queue.
@MainActor final class AudioMixer: ObservableObject {
    /// The key timed mutes and meters use for the system output.
    static let outputKey = "*output"

    @Published private(set) var devices: [AudioDevice] = []
    @Published private(set) var output = SystemDeviceState()
    @Published private(set) var input = SystemDeviceState()
    @Published private(set) var effects = SystemDeviceState()
    @Published private(set) var alertVolume: Double?
    @Published private(set) var rows: [MixerAppRow] = []
    @Published private(set) var configuration: AudioConfiguration
    /// Why the system output's effects are not running although they are set.
    @Published private(set) var systemError: String?
    @Published private(set) var timedMutes: [String: Date] = [:]
    let meters = MeterLevels()
    /// Whether the meters run while the mixer is on screen (each meter is a tap of its own).
    var metersEnabled = true
    /// The launcher's audio commands (devices, Quick Configs) changed.
    var onCommandsChange: (() -> Void)?

    private let store: AudioConfigStore
    private let engine = RouteEngine()
    private var groups: [AudioAppGroup] = []
    private var lastHeard: [String: Date] = [:]
    /// What the engine was last asked to run; the engine catches up in the background.
    private var running: [String: RouteStructure] = [:]
    private var routeErrors: [String: String] = [:]
    /// Routes that failed to build, so they are not tried again on every refresh. A change by the user clears them.
    private var failed: [String: RouteStructure] = [:]
    private var listeners: [(AudioObjectPropertyAddress, AudioObjectPropertyListenerBlock)] = []
    private var refreshPending = false
    private var visible = false
    private var refreshTimer: Timer?
    private var meterTimer: Timer?
    private var names: [String: (name: String, path: String?)] = [:]

    init(store: AudioConfigStore) {
        self.store = store
        configuration = store.configuration
    }

    var loadFailed: Bool { store.loadFailed }

    /// Reads everything once and follows the system from then on. The saved settings take effect here.
    func start() {
        guard listeners.isEmpty else { return }
        listeners = AudioProperty.listen(to: [kAudioHardwarePropertyDevices, kAudioHardwarePropertyDefaultOutputDevice, kAudioHardwarePropertyDefaultInputDevice,
                                              kAudioHardwarePropertyDefaultSystemOutputDevice, kAudioHardwarePropertyProcessObjectList]) { [weak self] in
            MainActor.assumeIsolated { self?.scheduleRefresh() }
        }
        refresh()
    }

    /// Takes every route apart, so each app plays as macOS plays it.
    func stopAll() {
        AudioProperty.stopListening(listeners)
        listeners = []
        refreshTimer?.invalidate()
        meterTimer?.invalidate()
        refreshTimer = nil
        meterTimer = nil
        visible = false
        engine.stopAll()
        running = [:]
        failed = [:]
        meters.set([:])
    }

    /// While the mixer is on screen, levels and "playing" are read every second (nothing tells us
    /// when another app or a volume key changes them) and the meters run.
    func setVisible(_ visible: Bool) {
        self.visible = visible
        refreshTimer?.invalidate()
        meterTimer?.invalidate()
        refreshTimer = nil
        meterTimer = nil
        if visible {
            alertVolume = SystemAudio.alertVolume()
            refreshTimer = repeating(1) { $0.refresh() }
            meterTimer = repeating(1.0 / 15) { $0.readMeters() }
        } else {
            meters.set([:])
        }
        refresh()
    }

    private func repeating(_ interval: TimeInterval, _ work: @escaping @MainActor (AudioMixer) -> Void) -> Timer {
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in MainActor.assumeIsolated { if let self { work(self) } } }
        RunLoop.main.add(timer, forMode: .common)
        return timer
    }

    /// Several changes often arrive at once (a device plugged in changes the list and the default).
    private func scheduleRefresh() {
        guard !refreshPending else { return }
        refreshPending = true
        DispatchQueue.main.async { [weak self] in
            self?.refreshPending = false
            self?.followOutputWithEffects()
            self?.refresh()
        }
    }

    private func refresh() {
        let found = SystemAudio.devices()
        if found != devices {
            devices = found
            onCommandsChange?()
        }
        readSystem()
        groups = AudioApps.group(SystemAudio.processes(), ownPID: getpid()) { Bundle(path: $0)?.bundleIdentifier }
        AudioApps.remember(groups, in: &lastHeard, now: Date())
        endTimedMutes()
        reconcile()
        rebuildRows()
    }

    private func readSystem() {
        func state(_ role: DeviceRole) -> SystemDeviceState {
            guard let id = SystemAudio.defaultDevice(role) else { return SystemDeviceState() }
            let rates = role == .effects ? [] : SystemAudio.sampleRates(id)
            return SystemDeviceState(device: devices.first { $0.id == id }, volume: SystemAudio.volume(id, role), canSetVolume: SystemAudio.canSetVolume(id, role),
                                     muted: SystemAudio.isMuted(id, role), canMute: SystemAudio.canMute(id, role),
                                     balance: SystemAudio.balance(id, role), canSetBalance: SystemAudio.canSetBalance(id, role),
                                     sampleRate: rates.isEmpty ? nil : SystemAudio.sampleRate(id), sampleRates: rates)
        }
        let next = (state(.output), state(.input), state(.effects))
        if next.0 != output { output = next.0 }
        if next.1 != input { input = next.1 }
        if next.2 != effects { effects = next.2 }
    }

    /// 「시스템 출력 따라가기」: the alert sounds move to wherever the output went.
    private func followOutputWithEffects() {
        guard configuration.effectsFollowOutput, let output = SystemAudio.defaultDevice(.output), SystemAudio.defaultDevice(.effects) != output else { return }
        SystemAudio.setDefault(.effects, to: output)
    }

    // MARK: Routes

    private func reconcile() {
        let connected = Set(devices.filter(\.hasOutput).map(\.uid))
        let ownProcess = SystemAudio.ownProcessObject()
        let muted = Set(timedMutes.keys)
        var plans = AudioRoutes.plan(groups: groups, settings: configuration.apps, system: configuration.system, outputGroups: configuration.outputGroups,
                                     defaultOutputUID: output.device?.uid, connected: connected, ownProcessID: ownProcess, muted: muted)
        if visible, metersEnabled {
            plans.merge(AudioRoutes.meterPlans(groups: groups, routed: Set(plans.keys))) { route, _ in route }
        }
        // A route that failed is not tried again until something about it changes.
        let wanted = plans.filter { failed[$0.key] != $0.value.structure }
        let changes = AudioRoutes.changes(running: running, desired: wanted)
        for key in changes.stop { running[key] = nil }
        for key in changes.start { running[key] = wanted[key]?.structure }
        engine.apply(changes, plans: wanted, devices: devices, clock: output.device) { [weak self] results in
            guard let self else { return }
            for (key, error) in results {
                if let error {
                    routeErrors[key] = error
                    failed[key] = running[key]
                    running[key] = nil
                } else {
                    routeErrors[key] = nil
                }
            }
            rebuildRows()
            updateSystemError()
        }
        // Settings gone back to the defaults leave no error behind.
        routeErrors = routeErrors.filter { plans[$0.key] != nil }
        failed = failed.filter { plans[$0.key] != nil }
        updateSystemError()
    }

    private func updateSystemError() {
        let next: String? = configuration.system.chain.isNeutral ? nil
            : SystemAudio.ownProcessObject() == nil ? "\(AppIdentity.name) 을(를) 오디오 시스템에서 찾지 못해 시스템 출력 효과를 켜지 않았습니다. 앱 하나의 소리를 바꾸면 다시 시도합니다."
            : routeErrors[AudioRoutes.systemKey]
        if next != systemError { systemError = next }
    }

    private func readMeters() {
        var next: [String: Float] = [:]
        for (key, level) in engine.levels() {
            if key == AudioRoutes.outputMeterKey {
                next[Self.outputKey] = level.input
            } else if key.hasPrefix(AudioRoutes.meterPrefix) {
                next[String(key.dropFirst(AudioRoutes.meterPrefix.count))] = level.input
            } else if key != AudioRoutes.systemKey {
                next[key] = level.output
            }
        }
        meters.set(next)
    }

    private func rebuildRows() {
        let connected = Set(devices.filter(\.hasOutput).map(\.uid))
        let appRows = AudioApps.rows(groups: groups, favorites: configuration.favorites, configured: Set(configuration.apps.keys),
                                     lastHeard: lastHeard, now: Date(), name: { self.appInfo($0, path: nil).name })
        let next = appRows.map { row in
            let settings = configuration.settings(for: row.key)
            let info = appInfo(row.key, path: row.group?.appPath)
            let chosen = settings.outputUID.map { AudioRoutes.outputs(for: $0, groups: configuration.outputGroups, defaultOutputUID: nil, connected: connected) }
            return MixerAppRow(key: row.key, name: info.name, appPath: info.path, row: row, settings: settings,
                               outputMissing: chosen?.isEmpty ?? false, routeError: routeErrors[row.key], timedMuteUntil: timedMutes[row.key])
        }
        if next != rows { rows = next }
    }

    /// The name and bundle of an app key, looked up once.
    func appInfo(_ key: String, path: String?) -> (name: String, path: String?) {
        if let known = names[key], known.path != nil || path == nil { return known }
        let bundle = path ?? (key.hasPrefix("path:") ? nil : NSWorkspace.shared.urlForApplication(withBundleIdentifier: key)?.path)
        let name: String
        if let bundle {
            name = FileManager.default.displayName(atPath: bundle).replacingOccurrences(of: ".app", with: "")
        } else if let known = AudioApps.knownNames[key] {
            name = known
        } else if key.hasPrefix("path:") {
            name = (String(key.dropFirst(5)) as NSString).lastPathComponent
        } else {
            name = key
        }
        names[key] = (name, bundle)
        return (name, bundle)
    }

    // MARK: System

    func select(_ role: DeviceRole, _ device: AudioDevice) {
        SystemAudio.setDefault(role, to: device.id)
        if role == .output { followOutputWithEffects() }
        refresh()
    }

    func setVolume(_ role: DeviceRole, _ volume: Double) {
        guard let id = state(role).device?.id else { return }
        SystemAudio.setVolume(id, role, volume)
        readSystem()
    }

    func toggleMute(_ role: DeviceRole) {
        guard let id = state(role).device?.id else { return }
        SystemAudio.setMuted(id, role, !(state(role).muted ?? false))
        readSystem()
    }

    func setBalance(_ role: DeviceRole, _ balance: Double) {
        guard let id = state(role).device?.id else { return }
        SystemAudio.setBalance(id, role, balance)
        readSystem()
    }

    func setSampleRate(_ role: DeviceRole, _ rate: Double) {
        guard let id = state(role).device?.id else { return }
        SystemAudio.setSampleRate(id, rate)
        refresh()
    }

    func setAlertVolume(_ volume: Double) {
        SystemAudio.setAlertVolume(volume)
        alertVolume = volume
    }

    func setEffectsFollowOutput(_ follows: Bool) {
        change { $0.effectsFollowOutput = follows }
        followOutputWithEffects()
        refresh()
    }

    func updateSystemEffects(_ edit: (inout SystemEffects) -> Void) {
        failed[AudioRoutes.systemKey] = nil
        change { edit(&$0.system) }
    }

    func state(_ role: DeviceRole) -> SystemDeviceState {
        switch role {
        case .output: return output
        case .input: return input
        case .effects: return effects
        }
    }

    func devices(for role: DeviceRole) -> [AudioDevice] {
        devices.filter { role == .input ? $0.hasInput : $0.hasOutput }
    }

    // MARK: Timed mute

    /// Mutes for a while; when the time is up the sound fades back in. The output is muted at the
    /// device, an app through its route.
    func muteFor(_ key: String, seconds: TimeInterval) {
        timedMutes[key] = Date().addingTimeInterval(seconds)
        if key == Self.outputKey, let id = output.device?.id { SystemAudio.setMuted(id, .output, true) }
        failed[key] = nil
        reconcile()
        rebuildRows()
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds + 0.05) { [weak self] in self?.endTimedMutes() }
    }

    func cancelTimedMute(_ key: String) {
        timedMutes[key] = Date.distantPast
        endTimedMutes()
    }

    private func endTimedMutes() {
        let now = Date()
        let ended = timedMutes.filter { $0.value <= now }.map(\.key)
        guard !ended.isEmpty else { return }
        for key in ended { timedMutes[key] = nil }
        if ended.contains(Self.outputKey), let id = output.device?.id { SystemAudio.setMuted(id, .output, false) }
        // The routes of apps whose mute ended glide back over a couple of seconds.
        reconcile(fadingIn: Set(ended))
        rebuildRows()
        readSystem()
    }

    private func reconcile(fadingIn keys: Set<String>) {
        reconcile()
        for key in keys where running[key] != nil {
            var chain = configuration.settings(for: key).chain()
            chain.glide = AudioGain.fadeIn
            if let structure = running[key] {
                engine.apply(RouteChanges(update: [key]), plans: [key: RoutePlan(structure: structure, chain: chain)], devices: devices, clock: output.device) { _ in }
            }
        }
    }

    // MARK: Apps

    func updateApp(_ key: String, _ edit: (inout AppAudioSettings) -> Void) {
        failed[key] = nil
        store.updateApp(key, edit)
        configurationChanged()
    }

    func resetApp(_ key: String) { updateApp(key) { $0 = AppAudioSettings() } }

    func toggleFavorite(_ key: String) { change { $0.toggleFavorite(key) } }

    func moveFavorite(_ key: String, by offset: Int) { change { $0.moveFavorite(key, by: offset) } }

    /// Running apps with a window, for 「즐겨찾기 더하기」, by name.
    func favoriteCandidates() -> [(key: String, name: String)] {
        let favorites = Set(configuration.favorites)
        var seen: Set<String> = []
        return NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { app in app.bundleIdentifier.map { ($0, app.localizedName ?? $0) } }
            .filter { !favorites.contains($0.0) && $0.0 != AppIdentity.bundleID && seen.insert($0.0).inserted }
            .sorted { $0.1.localizedCompare($1.1) == .orderedAscending }
            .map { (key: $0.0, name: $0.1) }
    }

    // MARK: Output groups

    @discardableResult func saveOutputGroup(id: UUID?, name: String, deviceUIDs: [String]) -> OutputGroup? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !deviceUIDs.isEmpty else { return nil }
        let group = OutputGroup(id: id ?? UUID(), name: trimmed, deviceUIDs: deviceUIDs)
        change { configuration in
            if let index = configuration.outputGroups.firstIndex(where: { $0.id == group.id }) {
                configuration.outputGroups[index] = group
            } else {
                configuration.outputGroups.append(group)
            }
        }
        failed = [:]
        return group
    }

    func removeOutputGroup(_ id: UUID) { change { $0.outputGroups.removeAll { $0.id == id } } }

    // MARK: Quick Configs

    var systemState: SystemAudioState {
        SystemAudioState(outputUID: output.device?.uid, outputVolume: output.volume, outputMuted: output.muted,
                         inputUID: input.device?.uid, inputVolume: input.volume,
                         effectsUID: configuration.effectsFollowOutput ? nil : effects.device?.uid, alertVolume: alertVolume ?? SystemAudio.alertVolume())
    }

    @discardableResult func saveQuickConfig(named name: String) -> Bool {
        let saved = store.saveQuickConfig(name: name, system: systemState) != nil
        configurationChanged()
        onCommandsChange?()
        return saved
    }

    func applyQuickConfig(_ id: UUID) {
        guard let config = configuration.quickConfigs.first(where: { $0.id == id }) else { return }
        failed = [:]
        store.update { $0.apply(config) }
        let system = config.system
        // A device that is not connected now is skipped; the rest still applies.
        func device(_ uid: String?) -> AudioDevice? { uid.flatMap { uid in devices.first { $0.uid == uid } } }
        if let device = device(system.outputUID) { SystemAudio.setDefault(.output, to: device.id) }
        if let device = device(system.inputUID) { SystemAudio.setDefault(.input, to: device.id) }
        if let device = device(system.effectsUID) { SystemAudio.setDefault(.effects, to: device.id) }
        readSystem()
        if let volume = system.outputVolume, let id = output.device?.id { SystemAudio.setVolume(id, .output, volume) }
        if let muted = system.outputMuted, let id = output.device?.id { SystemAudio.setMuted(id, .output, muted) }
        if let volume = system.inputVolume, let id = input.device?.id { SystemAudio.setVolume(id, .input, volume) }
        if let volume = system.alertVolume { setAlertVolume(volume) }
        followOutputWithEffects()
        configurationChanged()
    }

    func removeQuickConfig(_ id: UUID) {
        store.removeQuickConfig(id)
        configurationChanged()
        onCommandsChange?()
    }

    private func change(_ edit: (inout AudioConfiguration) -> Void) {
        store.update(edit)
        configurationChanged()
    }

    /// A slider being dragged lands here many times a second, so only the routes and rows follow;
    /// devices and processes are read again by the next refresh.
    private func configurationChanged() {
        configuration = store.configuration
        reconcile()
        rebuildRows()
    }
}
