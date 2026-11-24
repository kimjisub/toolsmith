import AppKit
import SwiftUI
import ToolsmithKit

/// 화면 나누기: window placements as commands and shortcuts. Nothing runs in the background.
@MainActor final class WindowsModule: AppModule {
    nonisolated static let descriptor = ModuleDescriptor(id: "windows", title: "화면 나누기", summary: "창을 화면의 절반, 3분의 1, 귀퉁이로 옮깁니다",
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
