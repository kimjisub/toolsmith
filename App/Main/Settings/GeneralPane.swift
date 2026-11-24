import AppKit
import SwiftUI
import ToolsmithKit

struct GeneralPane: View {
    @ObservedObject var environment: AppEnvironment
    @ObservedObject var settings: SettingsStore
    @State private var loginError: String?

    var body: some View {
        SettingsPage(title: "일반") {
            SettingsSection(title: "앱", footer: loginError ?? (LaunchAtLogin.isInstalled ? nil : "자동 실행은 응용 프로그램 폴더에 설치한 뒤에 적용됩니다.")) {
                ToggleRow(title: "로그인할 때 자동 실행", detail: "맥을 켜면 메뉴 막대에서 기다립니다", isOn: Binding(
                    // For an installed copy the system's own status is the truth.
                    get: { LaunchAtLogin.isInstalled ? LaunchAtLogin.isEnabled : settings.settings.launchAtLogin },
                    set: { setLaunchAtLogin($0) }))
            }
            SettingsSection(title: "입력창") {
                if environment.modules.isEnabled(LauncherModule.descriptor.id) {
                SettingsRow(title: "입력창 열기", detail: "어느 앱에서든 이 키로 입력창을 엽니다") {
                    HStack(spacing: Space.xs) {
                        ForEach(Array((settings.settings.hotkeys.combo(for: HotkeyID.openLauncher)?.displayParts ?? []).enumerated()), id: \.offset) { _, part in
                            KeyCap(label: part)
                        }
                    }
                    RowButton("바꾸기") { environment.settingsPane = .hotkeys }
                }
                }
                SettingsRow(title: "처음 안내 다시 보기", detail: "권한과 기능을 한 번에 다시 봅니다") {
                    RowButton("열기") { environment.onboarding.show() }
                }
            }
            SettingsSection(title: "기능과 메뉴 막대") {
                SettingsRow(title: "기능 고르기", detail: "쓰는 기능만 켜 둡니다") {
                    RowButton("기능") { environment.settingsPane = .features }
                }
                SettingsRow(title: "메뉴 막대 꾸미기", detail: "메뉴 막대에 보일 항목, 순서, 모양을 고릅니다") {
                    RowButton("메뉴 막대") { environment.settingsPane = .menuBar }
                }
            }
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        loginError = nil
        if LaunchAtLogin.isInstalled {
            do {
                try LaunchAtLogin.set(enabled)
            } catch {
                // The switch stays where it was; say why.
                loginError = "자동 실행을 바꾸지 못했습니다: \(error.localizedDescription)"
                return
            }
        }
        settings.update { $0.launchAtLogin = enabled }
    }
}

struct AboutPane: View {
    @ObservedObject var environment: AppEnvironment
    private var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "-" }
    private var build: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "-" }
    private var copyright: String { Bundle.main.object(forInfoDictionaryKey: "NSHumanReadableCopyright") as? String ?? "" }

    var body: some View {
        SettingsPage(title: "정보") {
            VStack(spacing: Space.m) {
                AppIconImage(size: 96)
                Text(AppIdentity.name).font(.role(.hero, weight: .semibold))
                Text("버전 \(version) (\(build))").font(.role(.secondary).monospacedDigit()).foregroundStyle(Ink.tertiary).textSelection(.enabled)
                Text("필요한 기능만 켜서 쓰는 맥 도구. 입력창, 클립보드, 화면 나누기, 캡처, AI 검색, 시스템 모니터, 소리 조절을 한 앱에서 씁니다.")
                    .font(.role(.secondary)).foregroundStyle(Ink.tertiary).multilineTextAlignment(.center).frame(maxWidth: 420)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Space.s)
            UpdateSection(updates: environment.updates, settings: environment.settings)
            SettingsSection {
                SettingsRow(title: "처음 안내", detail: "권한과 기능을 처음부터 다시 봅니다") {
                    RowButton("다시 보기") { environment.onboarding.show() }
                }
                SettingsRow(title: "저장 폴더", detail: "기록과 설정이 있는 곳. 이 맥에만 있습니다") {
                    RowButton("Finder 에서 보기") { NSWorkspace.shared.activateFileViewerSelecting([SettingsStore.supportDirectory]) }
                }
            }
            Text(copyright).font(.role(.detail)).foregroundStyle(Ink.tertiary).frame(maxWidth: .infinity)
        }
    }
}

/// The version's updates: whether they install by themselves, how the last check went, and a button to check now.
private struct UpdateSection: View {
    @ObservedObject var updates: UpdateController
    @ObservedObject var settings: SettingsStore

    var body: some View {
        SettingsSection(title: "업데이트", footer: updates.canUpdate
                        ? "새 버전은 개발자 서명과 애플 공증을 확인한 뒤에만 설치하고, 화면 녹화 중이면 끝날 때까지 기다립니다. 받거나 바꾸지 못한 버전은 알림으로 알리고 자동으로 다시 받지 않습니다."
                        : "개발 빌드와 직접 빌드한 앱은 업데이트를 확인하지 않습니다. 서명된 배포판에서만 동작합니다.") {
            ToggleRow(title: "자동으로 업데이트", detail: "6시간마다 확인해 새 버전이 있으면 받아서 바꾸고 다시 켭니다", isOn: settings.binding(\.automaticUpdates))
            SettingsRow(title: "마지막 확인", detail: updates.lastCheck.map { "\(RelativeTime.text(from: $0.at, now: Date())) · \($0.message)" } ?? "아직 확인하지 않았습니다") {
                if updates.isChecking {
                    Spinner()
                } else {
                    RowButton("지금 확인") { Task { await updates.check() } }.disabled(!updates.canUpdate)
                }
            }
        }
    }
}
