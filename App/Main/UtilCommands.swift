import AppKit
import ToolsmithKit

/// Commands about the app itself.
@MainActor final class UtilCommandSource: CommandSource {
    static let section = CommandSection(id: "util", title: AppIdentity.name, order: 20)
    static let settingsID = "util.settings"
    var openSettings: () -> Void = {}
    var openOnboarding: () -> Void = {}

    nonisolated func commands() -> [Command] {
        MainActor.assumeIsolated {
            [
                Command(id: Self.settingsID, title: "설정 열기", subtitle: nil, keywords: ["settings", "preferences", "환경설정", "단축키"],
                        section: Self.section, icon: .symbol("gearshape"), hotkeyID: Self.settingsID, launcherShortcut: "⌘,",
                        run: { [weak self] in self?.openSettings() }),
                Command(id: "util.onboarding", title: "처음 안내 다시 보기", subtitle: nil, keywords: ["onboarding", "welcome", "시작하기", "소개", "도움말"],
                        section: Self.section, icon: .symbol("hand.wave"), hotkeyID: nil,
                        run: { [weak self] in self?.openOnboarding() }),
                Command(id: "util.quit", title: "\(AppIdentity.name) 종료", subtitle: nil, keywords: ["quit", "exit"],
                        section: Self.section, icon: .symbol("power"), hotkeyID: nil,
                        run: { NSApp.terminate(nil) }),
            ]
        }
    }
}
