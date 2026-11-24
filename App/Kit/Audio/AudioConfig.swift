import Foundation

/// The Mac's own sound settings at one moment: what a Quick Config puts back. Devices are kept by
/// UID, which stays the same across restarts and reconnections.
public struct SystemAudioState: Codable, Equatable, Sendable {
    public var outputUID: String?
    public var outputVolume: Double?
    public var outputMuted: Bool?
    public var inputUID: String?
    public var inputVolume: Double?
    public var effectsUID: String?
    public var alertVolume: Double?

    public init(outputUID: String? = nil, outputVolume: Double? = nil, outputMuted: Bool? = nil, inputUID: String? = nil,
                inputVolume: Double? = nil, effectsUID: String? = nil, alertVolume: Double? = nil) {
        self.outputUID = outputUID
        self.outputVolume = outputVolume
        self.outputMuted = outputMuted
        self.inputUID = inputUID
        self.inputVolume = inputVolume
        self.effectsUID = effectsUID
        self.alertVolume = alertVolume
    }
}

/// A named set of sound settings, saved and brought back at once.
public struct QuickConfig: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public var name: String
    public var savedAt: Date
    public var system: SystemAudioState
    public var systemEffects: SystemEffects
    public var effectsFollowOutput: Bool
    public var apps: [String: AppAudioSettings]
    public var favorites: [String]

    public init(id: UUID, name: String, savedAt: Date, system: SystemAudioState, systemEffects: SystemEffects, effectsFollowOutput: Bool,
                apps: [String: AppAudioSettings], favorites: [String]) {
        self.id = id
        self.name = name
        self.savedAt = savedAt
        self.system = system
        self.systemEffects = systemEffects
        self.effectsFollowOutput = effectsFollowOutput
        self.apps = apps
        self.favorites = favorites
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        savedAt = try c.decodeIfPresent(Date.self, forKey: .savedAt) ?? Date(timeIntervalSince1970: 0)
        system = try c.decodeIfPresent(SystemAudioState.self, forKey: .system) ?? SystemAudioState()
        systemEffects = try c.decodeIfPresent(SystemEffects.self, forKey: .systemEffects) ?? SystemEffects()
        effectsFollowOutput = try c.decodeIfPresent(Bool.self, forKey: .effectsFollowOutput) ?? true
        apps = try c.decodeIfPresent([String: AppAudioSettings].self, forKey: .apps) ?? [:]
        favorites = try c.decodeIfPresent([String].self, forKey: .favorites) ?? []
    }
}

/// Everything the mixer keeps between launches.
public struct AudioConfiguration: Codable, Equatable, Sendable {
    public var schemaVersion = 1
    /// By app key (bundle id). Only apps with something changed are kept.
    public var apps: [String: AppAudioSettings] = [:]
    /// Pinned apps, in the order they are shown.
    public var favorites: [String] = []
    /// The effects of everything going to the system output.
    public var system = SystemEffects()
    /// Whether the alert sound device moves along when the system output changes (「시스템 출력 따라가기」).
    public var effectsFollowOutput = true
    public var outputGroups: [OutputGroup] = []
    public var quickConfigs: [QuickConfig] = []

    public init() {}

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        apps = try container.decodeIfPresent([String: AppAudioSettings].self, forKey: .apps) ?? [:]
        favorites = try container.decodeIfPresent([String].self, forKey: .favorites) ?? []
        system = try container.decodeIfPresent(SystemEffects.self, forKey: .system) ?? SystemEffects()
        effectsFollowOutput = try container.decodeIfPresent(Bool.self, forKey: .effectsFollowOutput) ?? true
        outputGroups = try container.decodeIfPresent([OutputGroup].self, forKey: .outputGroups) ?? []
        quickConfigs = try container.decodeIfPresent([QuickConfig].self, forKey: .quickConfigs) ?? []
        self = normalized()
    }

    public func settings(for key: String) -> AppAudioSettings { apps[key] ?? AppAudioSettings() }

    /// Defaults dropped, favorites without repeats, groups without devices dropped and apps that
    /// named a dropped group following the system again.
    public func normalized() -> AudioConfiguration {
        var copy = self
        copy.outputGroups = outputGroups.filter { !$0.deviceUIDs.isEmpty }
        let groupRefs = Set(copy.outputGroups.map(\.reference))
        copy.apps = apps.mapValues { app in
            var app = app
            if let output = app.outputUID, output.hasPrefix(OutputGroup.prefix), !groupRefs.contains(output) { app.outputUID = nil }
            return app
        }.filter { !$0.value.isDefault }
        var seen: Set<String> = []
        copy.favorites = favorites.filter { seen.insert($0).inserted }
        return copy
    }

    public mutating func toggleFavorite(_ key: String) {
        if favorites.contains(key) { favorites.removeAll { $0 == key } } else { favorites.append(key) }
    }

    /// Moves a favorite one place up (`offset` -1) or down (+1).
    public mutating func moveFavorite(_ key: String, by offset: Int) {
        guard let index = favorites.firstIndex(of: key) else { return }
        let target = index + offset
        guard favorites.indices.contains(target) else { return }
        favorites.swapAt(index, target)
    }

    /// Takes in a Quick Config's app settings, favorites and switches. The system devices are the caller's.
    public mutating func apply(_ config: QuickConfig) {
        apps = config.apps
        favorites = config.favorites
        system = config.systemEffects
        effectsFollowOutput = config.effectsFollowOutput
        self = normalized()
    }
}

/// The mixer's settings in `audio/audio.json`. They never leave the Mac.
public final class AudioConfigStore {
    public private(set) var configuration = AudioConfiguration()
    private var document: JSONDocument<AudioConfiguration>
    private let now: () -> Date

    public var loadFailed: Bool { document.loadFailed }

    public init(fileURL: URL, now: @escaping () -> Date = Date.init) {
        document = JSONDocument(fileURL: fileURL)
        self.now = now
        if let loaded = document.load(now: now()) { configuration = loaded }
    }

    public func update(_ change: (inout AudioConfiguration) -> Void) {
        var next = configuration
        change(&next)
        next = next.normalized()
        guard next != configuration else { return }
        configuration = next
        document.save(configuration)
    }

    public func updateApp(_ key: String, _ change: (inout AppAudioSettings) -> Void) {
        update { configuration in
            var app = configuration.settings(for: key)
            change(&app)
            configuration.apps[key] = app
        }
    }

    /// Saves the current settings under `name`, replacing a config of the same name. nil for an empty name.
    @discardableResult public func saveQuickConfig(name: String, system: SystemAudioState) -> QuickConfig? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let existing = configuration.quickConfigs.first { $0.name == trimmed }
        let config = QuickConfig(id: existing?.id ?? UUID(), name: trimmed, savedAt: now(), system: system,
                                 systemEffects: configuration.system, effectsFollowOutput: configuration.effectsFollowOutput,
                                 apps: configuration.apps, favorites: configuration.favorites)
        update { configuration in
            if let index = configuration.quickConfigs.firstIndex(where: { $0.id == config.id }) {
                configuration.quickConfigs[index] = config
            } else {
                configuration.quickConfigs.append(config)
            }
        }
        return config
    }

    public func removeQuickConfig(_ id: UUID) {
        update { $0.quickConfigs.removeAll { $0.id == id } }
    }
}
