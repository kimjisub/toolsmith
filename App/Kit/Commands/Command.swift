import Foundation

public enum CommandIcon: Equatable {
    /// An SF Symbol name.
    case symbol(String)
    /// A path whose Finder icon is shown (an app bundle, a file).
    case file(URL)
}

/// A titled group of results in the launcher. Lower `order` comes first.
public struct CommandSection: Hashable {
    public let id: String
    public let title: String
    public let order: Int

    public init(id: String, title: String, order: Int) {
        self.id = id
        self.title = title
        self.order = order
    }
}

/// One thing the launcher can run. Every feature registers itself as commands, so adding a
/// feature never means editing the launcher or the settings window.
public struct Command: Identifiable {
    /// Globally unique, stable across launches ("app:/Applications/Slack.app", "util.settings").
    public let id: String
    public let title: String
    public let subtitle: String?
    /// Extra words the command is found by, beyond its title.
    public let keywords: [String]
    public let section: CommandSection
    public let icon: CommandIcon
    /// Key into the hotkey table. nil for commands that cannot have a global shortcut (apps).
    public let hotkeyID: String?
    /// A shortcut that works only while the launcher is open ("⌘,"), shown when no global one is set.
    public let launcherShortcut: String?
    /// False for things that are not commands in the user's mind (a clipboard entry), so running
    /// one does not put it in the Recent list.
    public let tracksUsage: Bool
    /// True when running the command does not close the launcher: the launcher goes on to
    /// something else in place (a snippet whose variables are filled in there).
    public let keepsLauncherOpen: Bool
    public let run: @MainActor () -> Void

    public init(id: String, title: String, subtitle: String?, keywords: [String], section: CommandSection,
                icon: CommandIcon, hotkeyID: String?, launcherShortcut: String? = nil, tracksUsage: Bool = true, keepsLauncherOpen: Bool = false, run: @escaping @MainActor () -> Void) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.keywords = keywords
        self.section = section
        self.icon = icon
        self.hotkeyID = hotkeyID
        self.launcherShortcut = launcherShortcut
        self.tracksUsage = tracksUsage
        self.keepsLauncherOpen = keepsLauncherOpen
        self.run = run
    }

    /// A command whose title comes from a string catalog. It shows in the app's language and is
    /// found by its title in every language the app ships ("Left half" and "왼쪽 절반" alike).
    public init(id: String, localizedTitle: LocalizedStringResource, subtitle: String?, keywords: [String], section: CommandSection,
                icon: CommandIcon, hotkeyID: String?, launcherShortcut: String? = nil, tracksUsage: Bool = true, keepsLauncherOpen: Bool = false, run: @escaping @MainActor () -> Void) {
        var shown = localizedTitle
        shown.locale = .app
        let title = String(localized: shown)
        self.init(id: id, title: title, subtitle: subtitle, keywords: keywords + Localized.everyLanguage(localizedTitle).filter { $0 != title },
                  section: section, icon: icon, hotkeyID: hotkeyID, launcherShortcut: launcherShortcut, tracksUsage: tracksUsage,
                  keepsLauncherOpen: keepsLauncherOpen, run: run)
    }
}

public protocol CommandSource {
    /// Commands in the order they should appear when nothing else ranks them.
    func commands() -> [Command]
    /// Sections this source adds to the empty launcher, after "최근" (the clipboard's 「방금 복사한 것」).
    func emptyStateSections() -> [ResultSection]
}

extension CommandSource {
    public func emptyStateSections() -> [ResultSection] { [] }
}
