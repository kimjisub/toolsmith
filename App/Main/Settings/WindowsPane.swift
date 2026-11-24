import SwiftUI
import ToolsmithKit

/// Window snapping settings: the gap between tiled windows.
struct WindowsPane: View {
    @ObservedObject var settings: SettingsStore

    var body: some View {
        SettingsSection(title: String(localized: "Layout"), footer: String(localized: "The space left between snapped windows and at the edges of the screen.")) {
            SliderRow(title: String(localized: "Gap Between Windows"), value: settings.binding(\.windowGap), range: 0...24, step: 2) { $0 == 0 ? String(localized: "None") : String(localized: "\(Int($0)) pt") }
        }
    }
}
