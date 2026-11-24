import AppKit
import SwiftUI
import ToolsmithKit

/// Screen capture and recording settings: where captures go, what happens after, and what a recording includes.
struct CapturePane: View {
    @ObservedObject var settings: SettingsStore

    var body: some View {
        SettingsLead(text: String(localized: "Capture an area, a window or the whole screen. Each capture appears at the bottom left, where you can copy it, save it, pin it or recognize its text."))
        SettingsSection(title: String(localized: "After Capturing")) {
            SettingsRow(title: String(localized: "Save to"), detail: (CaptureCoordinator.folder(settings.settings).path as NSString).abbreviatingWithTildeInPath) {
                if settings.settings.captureFolder != nil {
                    RowButton(String(localized: "Use Desktop")) { settings.update { $0.captureFolder = nil } }
                }
                RowButton(String(localized: "Change…"), action: chooseFolder)
            }
            ToggleRow(title: String(localized: "Copy to clipboard after capturing"), detail: String(localized: "Paste right away without saving first"), isOn: settings.binding(\.captureCopiesToClipboard))
            PickerRow(title: String(localized: "Color format"), detail: String(localized: "How a color from the color picker is copied"), selection: settings.binding(\.colorFormat),
                      options: ColorFormat.allCases, label: \.title)
        }
        SettingsSection(title: String(localized: "Recording")) {
            ToggleRow(title: String(localized: "Include Mac audio"), detail: String(localized: "Video recordings only. GIFs have no sound"), isOn: settings.binding(\.recordSystemAudio))
            ToggleRow(title: String(localized: "Include microphone"), detail: String(localized: "macOS asks for microphone access the first time you record with this on"), isOn: settings.binding(\.recordMicrophone))
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = String(localized: "Choose")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        settings.update { $0.captureFolder = url.path }
    }
}
