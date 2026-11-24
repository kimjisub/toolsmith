import Combine
import Foundation

public struct Settings: Codable, Equatable {
    /// 2: modules and the menu bar layout replaced `screenTimeEnabled`, `menuBarMeters` and `menuBarReadout`.
    public static let currentSchema = 2
    public var schemaVersion: Int = Settings.currentSchema
    public var hotkeys: HotkeyTable = .defaults
    public var launchAtLogin: Bool = true
    /// Whether the "launch at login" default was already handed to the system once. After that the
    /// system's own setting is the truth, so a user who turns it off in System Settings stays off.
    public var loginItemInitialized: Bool = false
    /// Space between tiled windows and around the screen edges, in points.
    public var windowGap: Double = 0
    /// Actions whose default shortcut was already offered (see `HotkeyTable.seed`).
    public var seededHotkeys: Set<String> = []
    /// How long clipboard history is kept. Forever unless the user picks a period: history is
    /// never removed without the user asking for it.
    public var clipRetention: ClipRetention = .forever
    public var clipboardPaused: Bool = false
    /// Bundle ids of apps whose copies are never recorded.
    public var clipIgnoredApps: [String] = ClipboardPolicy.defaultIgnoredApps
    /// The OpenRouter model that answers AI questions.
    public var aiModel: String = AIRequest.defaultModel
    /// Where captures are saved. nil means the Desktop.
    public var captureFolder: String?
    /// Whether a new capture also goes to the clipboard.
    public var captureCopiesToClipboard: Bool = true
    public var colorFormat: ColorFormat = .hex
    /// Whether a screen recording includes the Mac's own sound, and the microphone.
    public var recordSystemAudio: Bool = false
    public var recordMicrophone: Bool = false
    /// Whether the first-run guide was finished (or skipped).
    public var onboardingCompleted: Bool = false
    /// Which feature modules the user switched on or off.
    public var modules = ModuleSwitches()
    /// What the menu bar shows, in what order and how.
    public var menuBarLayout = MenuBarLayout()
    /// Whether newer released builds are downloaded and installed by themselves.
    public var automaticUpdates: Bool = true
    /// Whether the network details ask Cloudflare for the address the internet sees.
    public var publicAddressLookup: Bool = true

    public init() {}

    /// Keys of schema 1 that schema 2 reads once and replaces.
    private enum LegacyKeys: String, CodingKey { case screenTimeEnabled, menuBarMeters, menuBarReadout }

    /// Fields a file lacks take their defaults, so an older file still loads.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let legacy = try decoder.container(keyedBy: LegacyKeys.self)
        hotkeys = try container.decodeIfPresent(HotkeyTable.self, forKey: .hotkeys) ?? .defaults
        launchAtLogin = try container.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? true
        loginItemInitialized = try container.decodeIfPresent(Bool.self, forKey: .loginItemInitialized) ?? false
        windowGap = max(0, try container.decodeIfPresent(Double.self, forKey: .windowGap) ?? 0)
        seededHotkeys = try container.decodeIfPresent(Set<String>.self, forKey: .seededHotkeys) ?? []
        clipRetention = (try? container.decodeIfPresent(ClipRetention.self, forKey: .clipRetention)) ?? .forever
        clipboardPaused = try container.decodeIfPresent(Bool.self, forKey: .clipboardPaused) ?? false
        clipIgnoredApps = try container.decodeIfPresent([String].self, forKey: .clipIgnoredApps) ?? ClipboardPolicy.defaultIgnoredApps
        let model = try container.decodeIfPresent(String.self, forKey: .aiModel)?.trimmingCharacters(in: .whitespaces) ?? ""
        aiModel = model.isEmpty ? AIRequest.defaultModel : model
        captureFolder = try container.decodeIfPresent(String.self, forKey: .captureFolder)
        captureCopiesToClipboard = try container.decodeIfPresent(Bool.self, forKey: .captureCopiesToClipboard) ?? true
        colorFormat = (try? container.decodeIfPresent(ColorFormat.self, forKey: .colorFormat)) ?? .hex
        recordSystemAudio = try container.decodeIfPresent(Bool.self, forKey: .recordSystemAudio) ?? false
        recordMicrophone = try container.decodeIfPresent(Bool.self, forKey: .recordMicrophone) ?? false
        onboardingCompleted = try container.decodeIfPresent(Bool.self, forKey: .onboardingCompleted) ?? false
        automaticUpdates = try container.decodeIfPresent(Bool.self, forKey: .automaticUpdates) ?? true
        publicAddressLookup = try container.decodeIfPresent(Bool.self, forKey: .publicAddressLookup) ?? true
        modules = (try? container.decodeIfPresent(ModuleSwitches.self, forKey: .modules)) ?? ModuleSwitches()
        if let layout = try? container.decodeIfPresent(MenuBarLayout.self, forKey: .menuBarLayout) {
            menuBarLayout = layout
        } else {
            // Schema 1: carry the menu bar over so it looks as it did. A file without the old keys
            // (a new install, or one that never changed them) gets the same readings as the default.
            let meters = (try? legacy.decodeIfPresent([String].self, forKey: .menuBarMeters)) ?? nil
            let readout = (try? legacy.decodeIfPresent(Bool.self, forKey: .menuBarReadout)) ?? nil
            if meters != nil || readout != nil {
                menuBarLayout = .legacy(meters: meters ?? MenuBarLayout.legacyMeters, readout: readout ?? true)
            }
        }
        if (try? legacy.decodeIfPresent(Bool.self, forKey: .screenTimeEnabled)) == false, modules.choices["screenTime"] == nil {
            modules = ModuleSwitches(modules.choices.merging(["screenTime": false]) { first, _ in first })
        }
        schemaVersion = Settings.currentSchema
    }
}

/// The user's settings, kept as one JSON file.
public final class SettingsStore: ObservableObject {
    @Published public private(set) var settings: Settings
    private let fileURL: URL

    /// `~/Library/Application Support/<bundle id>/`. A development build started with
    /// `TOOLSMITH_SUPPORT_DIR` keeps everything (settings, histories) there instead, so trying it on a
    /// Mac that runs the released app never touches the released app's data.
    public static var supportDirectory: URL {
        #if TOOLSMITH_DEV
        if let path = ProcessInfo.processInfo.environment["TOOLSMITH_SUPPORT_DIR"], !path.isEmpty {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        #endif
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(AppIdentity.bundleID, isDirectory: true)
    }

    public static var defaultURL: URL { supportDirectory.appendingPathComponent("settings.json") }

    public init(fileURL: URL) {
        self.fileURL = fileURL
        guard let data = try? Data(contentsOf: fileURL) else {
            settings = Settings()
            return
        }
        if let decoded = try? JSONDecoder().decode(Settings.self, from: data) {
            settings = decoded
        } else {
            // Start from defaults but keep the unreadable file for a person to look at.
            let aside = URL(fileURLWithPath: fileURL.path + ".broken")
            try? FileManager.default.removeItem(at: aside)
            try? FileManager.default.moveItem(at: fileURL, to: aside)
            settings = Settings()
        }
    }

    public func update(_ change: (inout Settings) -> Void) {
        var next = settings
        change(&next)
        guard next != settings else { return }
        settings = next
        save()
    }

    /// Changes the shortcut table with an operation that can refuse (clearing the launcher's key).
    /// Nothing is saved when it throws.
    public func updateHotkeys(_ change: (inout HotkeyTable) throws -> Void) throws {
        var table = settings.hotkeys
        try change(&table)
        update { $0.hotkeys = table }
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(settings) else { return }
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: fileURL, options: .atomic)
    }
}
