import AppKit
import SwiftUI
import ToolsmithKit

struct GeneralPane: View {
    @ObservedObject var environment: AppEnvironment
    @ObservedObject var settings: SettingsStore
    @State private var loginError: String?
    @State private var language = AppLanguagePreference.current

    var body: some View {
        SettingsPage(title: String(localized: "General")) {
            SettingsSection(title: String(localized: "App"), footer: loginError ?? (LaunchAtLogin.isInstalled ? nil : String(localized: "Launch at login takes effect once the app is installed in the Applications folder."))) {
                ToggleRow(title: String(localized: "Launch at Login"), detail: String(localized: "Waits in the menu bar when you start your Mac"), isOn: Binding(
                    // For an installed copy the system's own status is the truth.
                    get: { LaunchAtLogin.isInstalled ? LaunchAtLogin.isEnabled : settings.settings.launchAtLogin },
                    set: { setLaunchAtLogin($0) }))
            }
            SettingsSection(title: String(localized: "Language"), footer: language == AppLanguagePreference.launched ? nil : String(localized: "The new language is used after the app reopens.")) {
                PickerRow(title: String(localized: "App Language"), detail: String(localized: "Follows the system unless you choose one"),
                          selection: Binding(get: { language }, set: { language = $0; AppLanguagePreference.set($0) }),
                          options: AppLanguage.allCases, label: { $0.label() })
                if language != AppLanguagePreference.launched {
                    SettingsRow(title: String(localized: "Reopen to Apply")) {
                        RowButton(String(localized: "Reopen Now")) { Relaunch.now() }
                    }
                }
            }
            SettingsSection(title: String(localized: "Launcher")) {
                if environment.modules.isEnabled(LauncherModule.descriptor.id) {
                SettingsRow(title: String(localized: "Open Launcher"), detail: String(localized: "Opens the launcher from any app")) {
                    HStack(spacing: Space.xs) {
                        ForEach(Array((settings.settings.hotkeys.combo(for: HotkeyID.openLauncher)?.displayParts ?? []).enumerated()), id: \.offset) { _, part in
                            KeyCap(label: part)
                        }
                    }
                    RowButton(String(localized: "Change")) { environment.settingsPane = .hotkeys }
                }
                }
                SettingsRow(title: String(localized: "Show Welcome Guide Again"), detail: String(localized: "Goes over permissions and features again in one place")) {
                    RowButton(String(localized: "Open")) { environment.onboarding.show() }
                }
            }
            SettingsSection(title: String(localized: "Features and Menu Bar")) {
                SettingsRow(title: String(localized: "Choose Features"), detail: String(localized: "Keep on only the features you use")) {
                    RowButton(String(localized: "Features")) { environment.settingsPane = .features }
                }
                SettingsRow(title: String(localized: "Customize Menu Bar"), detail: String(localized: "Choose the items the menu bar shows, their order and their style")) {
                    RowButton(String(localized: "Menu Bar")) { environment.settingsPane = .menuBar }
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
                loginError = String(localized: "Couldn’t change launch at login: \(error.localizedDescription)")
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
        SettingsPage(title: String(localized: "About")) {
            VStack(spacing: Space.m) {
                AppIconImage(size: 96)
                Text(AppIdentity.name).font(.role(.hero, weight: .semibold))
                Text("Version \(version) (\(build))").font(.role(.secondary).monospacedDigit()).foregroundStyle(Ink.tertiary).textSelection(.enabled)
                Text("Mac utilities you switch on as you need them: launcher, clipboard, window snapping, capture, AI answers, system monitor and sound control in one app.")
                    .font(.role(.secondary)).foregroundStyle(Ink.tertiary).multilineTextAlignment(.center).frame(maxWidth: 420)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Space.s)
            UpdateSection(updates: environment.updates, settings: environment.settings)
            SettingsSection {
                SettingsRow(title: String(localized: "Welcome Guide"), detail: String(localized: "Goes over permissions and features from the start")) {
                    RowButton(String(localized: "Show Again")) { environment.onboarding.show() }
                }
                SettingsRow(title: String(localized: "Data Folder"), detail: String(localized: "Where history and settings are kept. Only on this Mac")) {
                    RowButton(String(localized: "Show in Finder")) { NSWorkspace.shared.activateFileViewerSelecting([SettingsStore.supportDirectory]) }
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
        SettingsSection(title: String(localized: "Updates"), footer: updates.canUpdate
                        ? String(localized: "A new version is installed only after its developer signature and Apple notarization are checked, and waits for a screen recording to finish. A version that can’t be downloaded or installed is reported in a notification and not downloaded again automatically.")
                        : String(localized: "Development builds and apps you build yourself don’t check for updates. Only signed releases do.")) {
            ToggleRow(title: String(localized: "Update Automatically"), detail: String(localized: "Checks every 6 hours and installs a new version, then reopens"), isOn: settings.binding(\.automaticUpdates))
            SettingsRow(title: String(localized: "Last Checked"), detail: updates.lastCheck.map { "\(RelativeTime.text(from: $0.at, now: Date())) · \($0.message)" } ?? String(localized: "Not checked yet")) {
                if updates.isChecking {
                    Spinner()
                } else {
                    RowButton(String(localized: "Check Now")) { Task { await updates.check() } }.disabled(!updates.canUpdate)
                }
            }
        }
    }
}
