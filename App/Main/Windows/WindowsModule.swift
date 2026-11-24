import AppKit
import SwiftUI
import ToolsmithKit

/// Window snapping: window placements as commands and shortcuts. Nothing runs in the background.
@MainActor final class WindowsModule: AppModule {
    nonisolated static let descriptor = ModuleDescriptor(id: "windows", title: String(localized: "Window Snapping"), summary: String(localized: "Moves windows to halves, thirds and corners of the screen"),
                                             symbol: "rectangle.split.2x1.fill", tint: .blue, permissions: [.accessibility])
    var descriptor: ModuleDescriptor { Self.descriptor }
    private let source = WindowCommandSource()

    init(host: ModuleHost) {
        source.target = { [weak host] in host?.targetApp }
        source.gap = { [weak host] in CGFloat(host?.settings.settings.windowGap ?? 0) }
        source.onFailure = { [weak host] text in host?.notify(text) }
    }

    var commandSources: [CommandSource] { [source] }
    var defaultHotkeys: [String: KeyCombo] { WindowAction.defaultHotkeys }
    func settingsGroups(in environment: AppEnvironment) -> AnyView? { AnyView(WindowsPane(settings: environment.settings)) }
    func start() {}
    func stop() {}
}
