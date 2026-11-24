import AppKit
import SwiftUI
import ToolsmithKit

/// A feature of the app that the user can switch on and off: the clipboard history, the system
/// monitor, window snapping… The app's shell (launcher, settings window, menu bar) only gathers
/// what the modules declare; it knows nothing about any one of them.
///
/// Adding a feature is a folder with its code and a module type, plus one line in `ModuleRegistry`.
/// `start()` runs when the module is switched on (and at launch), `stop()` when it is switched off
/// and when the app quits. Both may be called more than once. After `stop()` nothing of the module
/// may be left running: no timer, no observer, no open window, no system tap. Saved data stays.
@MainActor protocol AppModule: AnyObject {
    var descriptor: ModuleDescriptor { get }
    /// What the launcher and the global shortcuts offer while the module runs.
    var commandSources: [CommandSource] { get }
    /// Shortcuts offered once, the first time the module is seen (see `HotkeyTable.seed`).
    var defaultHotkeys: [String: KeyCombo] { get }
    /// Global shortcuts the module handles itself, outside any command (the launcher's own key).
    var hotkeyIDs: Set<String> { get }
    /// The drawing and the click of each item in `descriptor.menuBarItems`.
    var menuBarItems: [MenuBarItem] { get }
    /// Lines for the app menu (right click on the menu bar item).
    var appMenuItems: [AppMenuEntry] { get }
    /// The module's pages in the menu bar panel (see `PanelScreen`). A menu bar item opens its
    /// module's screen with `host.openPanel`.
    var panelScreens: [PanelScreen] { get }
    /// The groups of the module's settings page, built from the settings parts only
    /// (`SettingsSection` with `ToggleRow`, `PickerRow`, `SliderRow`, `FieldRow`, …). The page around
    /// them is drawn by the app: the module header with its switch on top, then these groups, then
    /// a 단축키 group with the module's shortcuts and a 권한 group with its permissions. nil: no
    /// groups of its own.
    func settingsGroups(in environment: AppEnvironment) -> AnyView?
    /// The shortcuts the page's 단축키 group lists. nil: every shortcut of the module's commands.
    var settingsShortcutIDs: [String]? { get }

    func start()
    func stop()

    /// The launcher is about to open.
    func launcherWillShow()
    /// Another window is about to take the screen: put floating panels away.
    func dismissPanels()
    /// A global shortcut is about to run `command`. True: the module handled it, run nothing.
    func willRunFromHotkey(_ command: Command) -> Bool
    /// The global shortcut `id` of `hotkeyIDs` was pressed.
    func hotkeyPressed(_ id: String)
    /// True while the module is in the middle of something an update must not cut short (a recording).
    var isBusy: Bool { get }
    /// Which of the module's menu bar items are on screen now (sampling can slow down when none is).
    func menuBarItemsShown(_ ids: Set<String>)
    #if TOOLSMITH_DEV
    /// Development flags of this module (`--show-monitor`, `--record-demo`…), run after launch.
    func runDevelopmentAid(_ arguments: [String])
    #endif
}

extension AppModule {
    var commandSources: [CommandSource] { [] }
    var defaultHotkeys: [String: KeyCombo] { [:] }
    var hotkeyIDs: Set<String> { [] }
    var menuBarItems: [MenuBarItem] { [] }
    var appMenuItems: [AppMenuEntry] { [] }
    var panelScreens: [PanelScreen] { [] }
    func settingsGroups(in environment: AppEnvironment) -> AnyView? { nil }
    var settingsShortcutIDs: [String]? { nil }
    func launcherWillShow() {}
    func dismissPanels() {}
    func willRunFromHotkey(_ command: Command) -> Bool { false }
    func hotkeyPressed(_ id: String) {}
    var isBusy: Bool { false }
    func menuBarItemsShown(_ ids: Set<String>) {}
    #if TOOLSMITH_DEV
    func runDevelopmentAid(_ arguments: [String]) {}
    #endif
}

/// What a module may ask of the app's shell.
@MainActor protocol ModuleHost: AnyObject {
    var settings: SettingsStore { get }
    var usage: UsageLog { get }
    var model: LauncherModel { get }
    var panel: LauncherPanel { get }
    /// The app that was in front when the launcher opened or a shortcut fired: what a window or
    /// paste action works on.
    var targetApp: NSRunningApplication? { get }
    /// True while a global shortcut is running its command.
    var isFiringHotkey: Bool { get }
    /// One line on screen, for a result or a failure.
    func notify(_ text: String)
    func openSettings(_ pane: SettingsPane?)
    /// A module's commands changed: the launcher and the shortcuts follow.
    func commandsChanged()
    /// Puts away every module's floating windows and the menu bar panel.
    func dismissPanels()
    /// Opens the menu bar panel on a screen under `anchor` (nil: under the app's first item), or
    /// closes it when that screen is already showing.
    func openPanel(_ screenID: String, below anchor: NSRect?)
    func closePanel()
    /// Where the app's menu bar item is on screen, for a panel opened from the app menu.
    func menuBarAnchor() -> NSRect?
    /// Another module, when it is running.
    func module<M: AppModule>(_ type: M.Type) -> M?
}

/// A line of the app menu.
struct AppMenuEntry {
    let title: String
    let symbol: String?
    let run: @MainActor () -> Void
}

extension ModuleTint {
    var color: Color {
        switch self {
        case .gray: return Tile.gray
        case .blue: return Tile.blue
        case .green: return Tile.green
        case .teal: return Tile.teal
        case .indigo: return Tile.indigo
        case .purple: return Tile.purple
        case .pink: return Tile.pink
        case .orange: return Tile.orange
        }
    }
}
