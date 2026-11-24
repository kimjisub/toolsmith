import AppKit
import ToolsmithKit

/// Installed apps as launcher commands.
@MainActor final class AppCommandSource: CommandSource {
    static let section = CommandSection(id: "apps", title: "앱", order: 10)
    private var entries: [AppEntry] = []
    /// Called on the main thread after a rescan found a different set of apps.
    var onChange: (() -> Void)?
    private var scanning = false

    /// Rescans off the main thread. The launcher keeps showing the previous list meanwhile,
    /// so opening it never waits for the disk.
    func refresh() {
        guard !scanning else { return }
        scanning = true
        Task.detached(priority: .utility) {
            let found = AppCatalog.scan(AppCatalog.defaultDirectories) {
                FileManager.default.displayName(atPath: $0.path)
            }
            await MainActor.run {
                self.scanning = false
                guard found != self.entries else { return }
                self.entries = found
                self.onChange?()
            }
        }
    }

    nonisolated func commands() -> [Command] {
        MainActor.assumeIsolated {
            let nameCounts = Dictionary(grouping: entries, by: \.name).mapValues(\.count)
            return entries.map { entry in
                Command(
                    id: "app:\(entry.url.path)",
                    title: entry.name,
                    // Two apps with one name are told apart by where they live.
                    subtitle: (nameCounts[entry.name] ?? 0) > 1 ? entry.url.deletingLastPathComponent().path : nil,
                    keywords: entry.alternateNames,
                    section: Self.section,
                    icon: .file(entry.url),
                    hotkeyID: nil,
                    run: { NSWorkspace.shared.openApplication(at: entry.url, configuration: .init()) }
                )
            }
        }
    }
}

/// 앱 실행: installed apps as launcher commands.
@MainActor final class AppsModule: AppModule {
    nonisolated static let descriptor = ModuleDescriptor(id: "apps", title: "앱 실행", summary: "설치된 앱을 이름으로 찾아 엽니다",
                                             symbol: "square.grid.2x2", tint: .blue, requires: [LauncherModule.descriptor.id])
    var descriptor: ModuleDescriptor { Self.descriptor }
    private unowned let host: ModuleHost
    private let source = AppCommandSource()

    init(host: ModuleHost) {
        self.host = host
        source.onChange = { [weak host] in host?.commandsChanged() }
    }

    var commandSources: [CommandSource] { [source] }
    func start() { source.refresh() }
    func stop() {}
    func launcherWillShow() { source.refresh() }
}
