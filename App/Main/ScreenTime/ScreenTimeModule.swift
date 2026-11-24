import AppKit
import SwiftUI
import ToolsmithKit

/// Screen time: which app was in front, and for how long. Switched off, nothing is counted.
@MainActor final class ScreenTimeModule: AppModule {
    nonisolated static let descriptor = ModuleDescriptor(id: "screenTime", title: String(localized: "Screen Time"), summary: String(localized: "Records on this Mac only how long you used each app. Deleted after 90 days"),
                                             symbol: "hourglass", tint: .indigo)
    var descriptor: ModuleDescriptor { Self.descriptor }
    static let openID = "util.screentime"
    /// nil when the usage file could not be opened.
    let store: ScreenTimeStore?
    private let tracker: ScreenTimeTracker?
    private let source: ScreenTimeCommandSource

    init(host: ModuleHost) {
        store = try? ScreenTimeStore(directory: SettingsStore.supportDirectory.appendingPathComponent("screentime", isDirectory: true))
        tracker = store.map(ScreenTimeTracker.init(store:))
        source = ScreenTimeCommandSource(open: { [weak host] in host?.openSettings(.screenTime) })
    }

    var commandSources: [CommandSource] { [source] }
    func settingsGroups(in environment: AppEnvironment) -> AnyView? { AnyView(ScreenTimePane(screenTime: self)) }
    func start() { tracker?.start() }
    func stop() { tracker?.stop() }

    /// Writes the time collected in memory, so a report loses nothing.
    func flush() { tracker?.flush() }
}

@MainActor private final class ScreenTimeCommandSource: CommandSource {
    private let open: @MainActor () -> Void
    init(open: @escaping @MainActor () -> Void) { self.open = open }

    nonisolated func commands() -> [Command] {
        MainActor.assumeIsolated { [Command(id: ScreenTimeModule.openID, localizedTitle: "Show Screen Time", subtitle: nil, keywords: ["screen time", "스크린타임", "통계", "인사이트", "얼마나 썼나"],
                 section: UtilCommandSource.section, icon: .symbol("hourglass"), hotkeyID: ScreenTimeModule.openID, run: open)] }
    }
}
