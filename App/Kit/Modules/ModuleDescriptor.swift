import Foundation

/// The color behind a module's icon in the settings window: one of the palette's tiles.
public enum ModuleTint: String, CaseIterable, Sendable {
    case gray, blue, green, teal, indigo, purple, pink, orange
}

/// A macOS permission a module uses. The settings show only the ones the switched-on modules need.
public enum ModulePermission: String, CaseIterable, Sendable {
    case accessibility, screenRecording, clipboard, microphone, audioCapture, location
}

/// How a menu bar item is drawn. An item offers the ones that make sense for it.
public enum MenuBarStyle: String, Codable, CaseIterable, Sendable {
    case icon, iconAndValue, value, graph

    public var label: String {
        switch self {
        case .icon: return "아이콘"
        case .iconAndValue: return "아이콘과 수치"
        case .value: return "수치"
        case .graph: return "그래프"
        }
    }
}

/// Something a module can put in the menu bar.
public struct MenuBarItemDescriptor: Identifiable, Equatable, Sendable {
    /// Stable, and starts with the module's id ("monitor.cpu").
    public let id: String
    public let moduleID: String
    public let title: String
    public let symbol: String
    /// The styles this item can be drawn in; never empty.
    public let styles: [MenuBarStyle]
    public let defaultStyle: MenuBarStyle
    public let defaultVisible: Bool

    public init(id: String, moduleID: String, title: String, symbol: String, styles: [MenuBarStyle],
                defaultStyle: MenuBarStyle? = nil, defaultVisible: Bool) {
        precondition(!styles.isEmpty, "a menu bar item needs at least one style")
        self.id = id
        self.moduleID = moduleID
        self.title = title
        self.symbol = symbol
        self.styles = styles
        self.defaultStyle = defaultStyle.flatMap { styles.contains($0) ? $0 : nil } ?? styles[0]
        self.defaultVisible = defaultVisible
    }

    /// The app's own icon. Shown by itself whenever nothing else is.
    public static let appIcon = MenuBarItemDescriptor(id: "app.icon", moduleID: "app", title: "앱 아이콘", symbol: "command",
                                                      styles: [.icon], defaultVisible: false)
}

/// What a feature module says about itself: enough for the settings window, the menu bar and the
/// permission list to show it without knowing anything else about it.
public struct ModuleDescriptor: Identifiable, Equatable, Sendable {
    /// Stable: the settings file, the settings window and menu bar item ids use it.
    public let id: String
    public let title: String
    /// One line, shown under the title in the list of features.
    public let summary: String
    public let symbol: String
    public let tint: ModuleTint
    public let defaultEnabled: Bool
    /// False for a module that is always on.
    public let canDisable: Bool
    /// Modules that must be on for this one to work.
    public let requires: [String]
    public let permissions: [ModulePermission]
    public let menuBarItems: [MenuBarItemDescriptor]

    public init(id: String, title: String, summary: String, symbol: String, tint: ModuleTint, defaultEnabled: Bool = true,
                canDisable: Bool = true, requires: [String] = [], permissions: [ModulePermission] = [], menuBarItems: [MenuBarItemDescriptor] = []) {
        self.id = id
        self.title = title
        self.summary = summary
        self.symbol = symbol
        self.tint = tint
        self.defaultEnabled = defaultEnabled
        self.canDisable = canDisable
        self.requires = requires
        self.permissions = permissions
        self.menuBarItems = menuBarItems
    }
}
