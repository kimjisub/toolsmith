import AppKit
import ToolsmithKit

/// 입력창: the launcher panel and its global shortcut. Switched off, the app is menu bar and
/// shortcuts only, and the modules that live inside the launcher stop with it.
@MainActor final class LauncherModule: AppModule {
    nonisolated static let descriptor = ModuleDescriptor(id: "launcher", title: "입력창", summary: "어느 앱에서든 단축키로 불러 앱, 명령, 기록을 찾아 실행합니다",
                                             symbol: "command", tint: .gray)
    var descriptor: ModuleDescriptor { Self.descriptor }
    private unowned let host: ModuleHost

    init(host: ModuleHost) { self.host = host }

    var hotkeyIDs: Set<String> { [HotkeyID.openLauncher] }
    var appMenuItems: [AppMenuEntry] {
        [AppMenuEntry(title: "입력창 열기", symbol: "command") { [weak self] in self?.host.panel.show() }]
    }

    func start() {}
    func stop() { host.panel.hide() }
    func hotkeyPressed(_ id: String) { host.panel.toggle() }
}
