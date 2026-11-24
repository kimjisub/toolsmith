import SwiftUI
import ToolsmithKit

/// The sound control's groups on its settings page. The page's header, shortcuts and permissions
/// are drawn by the settings window around them.
struct AudioSettingsGroups: View {
    @ObservedObject var mixer: AudioMixer
    let open: () -> Void

    var body: some View {
        if mixer.loadFailed {
            Notice(text: String(localized: "The saved sound settings could not be read and were moved to audio.broken.json. The defaults are in use for now."))
        }
        SettingsSection(title: String(localized: "Open"), footer: String(localized: "Click the speaker in the menu bar, or choose “Open Sound” in the launcher. Whether the speaker shows in the menu bar, and with the volume, is set in Menu Bar. The launcher also lists commands that switch the output and input device, and your saved Quick Configs.")) {
            SettingsRow(title: String(localized: "Sound")) { RowButton(String(localized: "Open"), action: open) }
        }
        SettingsSection(title: String(localized: "How app sound is changed"), footer: String(localized: "Apps you have not changed play as macOS plays them. When you change one app’s volume, output or effects, only that app’s audio is received, changed and played on the device you chose. Turning this feature off or quitting the app puts every app back as it was. Without permission, apps you changed go silent: allow it, or reset those apps.")) {
            SettingsRow(title: String(localized: "Changed apps"), detail: mixer.configuration.apps.isEmpty ? String(localized: "None") : String(localized: "\(mixer.configuration.apps.count) apps")) {
                RowButton(String(localized: "Reset All"), role: .destructive) { mixer.configuration.apps.keys.forEach(mixer.resetApp) }
            }
            SettingsRow(title: String(localized: "Quick Configs"), detail: mixer.configuration.quickConfigs.isEmpty ? String(localized: "None") : mixer.configuration.quickConfigs.map(\.name).joined(separator: ", "))
            SettingsRow(title: String(localized: "Output groups"), detail: mixer.configuration.outputGroups.isEmpty ? String(localized: "None") : mixer.configuration.outputGroups.map(\.name).joined(separator: ", "))
        }
    }
}
