import AppKit
import SwiftUI

/// A screen a module shows in the menu bar panel: the one floating panel that opens under the
/// app's menu bar items. The panel draws what every screen shares (the title, the switcher between
/// screens, the pin, the way to the module's settings, the footer); the screen draws only its own
/// content, at its own width, as tall as it needs (the panel follows its height, animated).
struct PanelScreen: Identifiable {
    /// Unique among screens; usually the module's id.
    let id: String
    let title: String
    let symbol: String
    /// The content width. Screens are narrow columns; 340 is the usual.
    var width: CGFloat = PanelScreen.standardWidth
    /// The module whose settings page the panel's gear opens.
    var settings: SettingsPane?
    /// The content, made each time the screen comes up (nothing of it lives while it is not shown).
    let content: @MainActor () -> AnyView
    /// The screen is on screen in this window (for windows the screen opens beside it).
    var onShow: (@MainActor (NSWindow) -> Void)?
    /// The screen went away (another screen was picked, or the panel closed).
    var onHide: (@MainActor () -> Void)?
    /// Windows the screen opened beside the panel. A click in them does not close the panel.
    var auxiliaryWindows: (@MainActor () -> [NSWindow])?

    static let standardWidth: CGFloat = 340
}
