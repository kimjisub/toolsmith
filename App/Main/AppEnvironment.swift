import AppKit
import Combine
import Foundation
import ToolsmithKit

/// The app's shell: settings, the launcher, global shortcuts, the settings window and the menu bar.
/// The features themselves are modules (`ModuleRegistry`); the shell gathers what they declare and
/// knows nothing about any one of them.
@MainActor final class AppEnvironment: ObservableObject, ModuleHost {
    let settings: SettingsStore
    let hotkeys = HotkeyRegistrar()
    let usage: UsageLog
    let engine: LauncherEngine
    let model: LauncherModel
    let panel: LauncherPanel
    let ai = AISession()
    private let util = UtilCommandSource()
    private(set) lazy var modules: ModuleManager = {
        ModuleManager(modules: ModuleRegistry.make(host: self), settings: settings)
    }()
    private(set) lazy var menuBar = MenuBarController(environment: self)
    /// The `toolsmith` command line tool's way in.
    private lazy var commandLineServer = CLIServer(modules: modules)
    private(set) lazy var updates = UpdateController(settings: settings, isBusy: { [weak self] in self?.modules.running.contains(where: \.isBusy) ?? false })
    /// The app in front when the launcher opened or a shortcut fired.
    private(set) var targetApp: NSRunningApplication?
    /// True while a global shortcut is running its command.
    private(set) var isFiringHotkey = false
    /// Shortcuts the system refused to register (another app holds the key).
    @Published private(set) var failedHotkeys: [String: KeyCombo] = [:]
    /// Shortcuts macOS itself uses, read when the settings window opens.
    @Published private(set) var systemShortcuts: Set<KeyCombo> = []
    @Published var settingsPane: SettingsPane = .general
    private lazy var settingsWindow = SettingsWindowController(environment: self)
    private(set) lazy var onboarding = OnboardingWindowController(settings: settings)
    private var hotkeysSuspended = false
    /// The shortcut row waiting for a key press, if any.
    @Published private(set) var recordingHotkeyID: String?
    private let recorder = HotkeyRecorder()
    private var subscriptions: Set<AnyCancellable> = []

    init() {
        settings = SettingsStore(fileURL: SettingsStore.defaultURL)
        usage = UsageLog(fileURL: SettingsStore.supportDirectory.appendingPathComponent("usage.json"))
        engine = LauncherEngine(sources: [], usage: usage)
        model = LauncherModel(engine: engine, usage: usage)
        // Off until the AI module starts.
        model.allowsAI = false
        // The panel exists from launch, so the shortcut only has to show it.
        panel = LauncherPanel(model: model, settings: settings, ai: ai)
        panel.aiKey = { KeyStore.key }
        panel.onNeedsAIKey = { [weak self] in self?.openSettings(.ai) }
        ai.model = { [weak self] in self?.settings.settings.aiModel ?? AIRequest.defaultModel }
        panel.onWillShow = { [weak self] in
            self?.cancelRecording()
            self?.modules.running.forEach { $0.launcherWillShow() }
        }
        panel.onWillRun = { [weak self] in self?.targetApp = self?.panel.previousApp }
        util.openSettings = { [weak self] in self?.openSettings() }
        util.openOnboarding = { [weak self] in self?.onboarding.show() }
        panel.onOpenSettings = { [weak self] in self?.openSettings() }
        // The first run of an installed copy turns "launch at login" on, as the default says.
        // Only once: after that, what the user chose in System Settings stands.
        if LaunchAtLogin.isInstalled, !settings.settings.loginItemInitialized {
            if settings.settings.launchAtLogin { try? LaunchAtLogin.set(true) }
            settings.update { $0.loginItemInitialized = true }
        }
        hotkeys.onFire = { [weak self] id in self?.fire(id) }
    }

    /// Starts the modules that are switched on and puts the app in the menu bar.
    func launch() {
        seedHotkeys()
        modules.onChange = { [weak self] in self?.modulesChanged() }
        modules.activate()
        modulesChanged()
        settings.$settings
            .map(\.hotkeys)
            .removeDuplicates()
            .sink { [weak self] table in self?.applyHotkeys(table) }
            .store(in: &subscriptions)
        updates.launch()
        commandLineServer.start()
    }

    /// Stops every module, for the app quitting.
    func terminate() {
        commandLineServer.stop()
        modules.deactivate()
    }

    /// New features bring default shortcuts; each is offered once (see HotkeyTable.seed), whether
    /// its module is on or not, so switching it on later finds its key.
    private func seedHotkeys() {
        var table = settings.settings.hotkeys
        let defaults = modules.modules.reduce(into: [String: KeyCombo]()) { all, module in
            all.merge(module.defaultHotkeys) { first, _ in first }
        }
        let seeded = table.seed(defaults, alreadySeeded: settings.settings.seededHotkeys)
        if !seeded.isEmpty {
            settings.update {
                $0.hotkeys = table
                $0.seededHotkeys.formUnion(seeded)
            }
        }
    }

    /// Modules started or stopped: the launcher, the shortcuts and the menu bar follow.
    private func modulesChanged() {
        engine.sources = modules.running.flatMap(\.commandSources) + [util]
        commandsChanged()
        menuBar.panel.reloadScreens()
        menuBar.rebuild()
    }

    // MARK: ModuleHost

    func notify(_ text: String) { panel.showNotice(text) }

    func commandsChanged() {
        engine.reload()
        model.refresh()
        applyHotkeys(settings.settings.hotkeys)
    }

    func dismissPanels() {
        modules.running.forEach { $0.dismissPanels() }
        menuBar.panel.hide()
    }

    func openPanel(_ screenID: String, below anchor: NSRect?) { menuBar.panel.toggle(screenID, below: anchor) }

    func closePanel() { menuBar.panel.hide() }

    func menuBarAnchor() -> NSRect? { menuBar.anchor }

    func module<M: AppModule>(_ type: M.Type) -> M? { modules.running(type) }

    func openSettings(_ pane: SettingsPane? = nil) {
        dismissPanels()
        panel.hide()
        settingsWindow.show(pane)
    }

    // MARK: Shortcuts

    /// Waits for one key press in the settings window. Our own global shortcuts are let go
    /// meanwhile, so the user can press one of them to move it.
    func beginRecording(_ id: String, _ handler: @escaping (RecordedKey) -> Void) {
        cancelRecording()
        recordingHotkeyID = id
        suspendHotkeys()
        recorder.start(in: settingsWindow.window) { [weak self] key in
            self?.recordingHotkeyID = nil
            self?.resumeHotkeys()
            handler(key)
        }
    }

    func cancelRecording() {
        recorder.stop()
        recordingHotkeyID = nil
        resumeHotkeys()
    }

    func refreshSystemShortcuts() {
        systemShortcuts = SystemShortcuts.current()
    }

    /// Lets go of every global shortcut while the settings window records a new one.
    func suspendHotkeys() {
        hotkeysSuspended = true
        hotkeys.unregisterAll()
    }

    func resumeHotkeys() {
        guard hotkeysSuspended else { return }
        hotkeysSuspended = false
        applyHotkeys(settings.settings.hotkeys)
    }

    /// The shortcuts of the commands that exist now, and those the running modules handle themselves.
    private var liveHotkeyIDs: Set<String> {
        Set(engine.hotkeyCommands().compactMap(\.hotkeyID)).union(modules.running.flatMap(\.hotkeyIDs))
    }

    private func applyHotkeys(_ table: HotkeyTable) {
        guard !hotkeysSuspended else { return }
        let registrable = table.registrable(live: liveHotkeyIDs)
        failedHotkeys = hotkeys.apply(registrable)
        NSLog("hotkeys registered: %d, refused: %d", registrable.bindings.count - failedHotkeys.count, failedHotkeys.count)
    }

    private func fire(_ id: String) {
        if let module = modules.running.first(where: { $0.hotkeyIDs.contains(id) }) {
            // On the guide's first page the launcher's shortcut is being tried out, not used.
            if id == HotkeyID.openLauncher, onboarding.isShowing, onboarding.model.step == .welcome {
                onboarding.model.launcherHotkeyPressed()
                return
            }
            module.hotkeyPressed(id)
        } else if let command = engine.command(hotkeyID: id) {
            // A shortcut pressed while the launcher is open still means the app behind it.
            // Only an open launcher stands over another app. A notice does not.
            targetApp = panel.isOpen ? panel.previousApp : NSWorkspace.shared.frontmostApplication
            if modules.running.contains(where: { $0.willRunFromHotkey(command) }) { return }
            isFiringHotkey = true
            defer { isFiringHotkey = false }
            if command.keepsLauncherOpen {
                // A snippet with variables, or the snippet search: the launcher comes up showing it.
                panel.showForFill { [model] in model.activate(id: command.id) }
            } else {
                panel.hide()
                model.activate(id: command.id)
            }
        }
    }
}
