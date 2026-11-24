import AppKit
import ToolsmithKit

/// The launcher panel and its global shortcut. Switched off, the app is menu bar and
/// shortcuts only, and the modules that live inside the launcher stop with it.
@MainActor final class LauncherModule: AppModule {
    nonisolated static let descriptor = ModuleDescriptor(id: "launcher", title: String(localized: "Launcher"), summary: String(localized: "Call it up from any app with a shortcut to find and run apps, commands and history"),
                                             symbol: "command", tint: .gray)
    var descriptor: ModuleDescriptor { Self.descriptor }
    private unowned let host: ModuleHost

    init(host: ModuleHost) { self.host = host }

    var hotkeyIDs: Set<String> { [HotkeyID.openLauncher] }
    var appMenuItems: [AppMenuEntry] {
        [AppMenuEntry(title: String(localized: "Open Launcher"), symbol: "command") { [weak self] in self?.host.panel.show() }]
    }

    func start() {}
    func stop() { host.panel.hide() }
    func hotkeyPressed(_ id: String) { host.panel.toggle() }
}
