import AppKit
import Combine
import SwiftUI
import ToolsmithKit

/// 캡처와 녹화: screenshots, recordings, text recognition, the color picker and the ruler.
@MainActor final class CaptureModule: AppModule {
    nonisolated static let descriptor = ModuleDescriptor(
        id: "capture", title: "캡처와 녹화", summary: "영역, 창, 스크롤 캡처와 주석, 글자 인식, 영상과 GIF 녹화",
        symbol: "camera.viewfinder", tint: .pink, permissions: [.screenRecording, .microphone],
        menuBarItems: [MenuBarItemDescriptor(id: "capture.icon", moduleID: "capture", title: "캡처", symbol: "camera.viewfinder",
                                             styles: [.icon], defaultVisible: false)])
    var descriptor: ModuleDescriptor { Self.descriptor }
    let coordinator = CaptureCoordinator()
    private let source: CaptureCommandSource

    private unowned let host: ModuleHost

    init(host: ModuleHost) {
        self.host = host
        // Leftovers of earlier runs: capture previews and unfinished recordings.
        for name in ["captures", "recordings"] {
            try? FileManager.default.removeItem(at: FileManager.default.temporaryDirectory.appendingPathComponent("\(AppIdentity.bundleID).\(name)", isDirectory: true))
        }
        source = CaptureCommandSource(coordinator: coordinator)
        coordinator.settings = { [weak host] in host?.settings.settings ?? Settings() }
        coordinator.notify = { [weak host] text in host?.notify(text) }
        coordinator.onNeedsPermission = { [weak host] in host?.openSettings(.capture) }
        coordinator.onEdit = { [weak self, weak host] image, screen in
            AnnotationEditorWindow.show(image, on: screen,
                onCopy: { result in
                    CaptureCoordinator.copy(result)
                    host?.notify("주석을 넣은 그림을 복사했습니다.")
                },
                onSave: { result in self?.coordinator.save(result) })
        }
    }

    var commandSources: [CommandSource] { [source] }
    var defaultHotkeys: [String: KeyCombo] { CaptureCommandSource.defaultHotkeys }
    var isBusy: Bool { coordinator.isRecording || coordinator.isFinishingRecording }
    func settingsGroups(in environment: AppEnvironment) -> AnyView? { AnyView(CapturePane(settings: environment.settings)) }

    var menuBarItems: [MenuBarItem] {
        [.icon(Self.descriptor.menuBarItems[0]) { [weak self] frame in self?.host.openPanel(Self.descriptor.id, below: frame) }]
    }

    var panelScreens: [PanelScreen] {
        [PanelScreen(id: Self.descriptor.id, title: "캡처와 녹화", symbol: "camera.viewfinder", settings: .capture, content: { [weak self] in
            guard let self else { return AnyView(EmptyView()) }
            let commands = self.source.commands().filter { $0.id != CaptureCommandSource.stopID || self.coordinator.isRecording }
            return AnyView(CapturePanelScreen(commands: commands, isRecording: self.coordinator.isRecording) { [weak self] command in
                self?.host.closePanel()
                // Let the panel leave the screen before the overlay or the picture is taken.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { command.run() }
            })
        })]
    }

    func start() {}

    /// A recording under way is finished and saved, not thrown away.
    func stop() {
        if coordinator.isRecording { coordinator.stopRecording() }
    }
}
