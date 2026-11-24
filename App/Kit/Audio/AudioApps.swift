import Foundation

/// One client process of the audio system, as Core Audio reports it.
public struct AudioProcessEntry: Equatable, Sendable {
    public let objectID: UInt32
    public let pid: Int32
    public let bundleID: String?
    public let executablePath: String?
    /// Whether it is sending sound out right now.
    public let isPlaying: Bool

    public init(objectID: UInt32, pid: Int32, bundleID: String?, executablePath: String?, isPlaying: Bool) {
        self.objectID = objectID
        self.pid = pid
        self.bundleID = bundleID
        self.executablePath = executablePath
        self.isPlaying = isPlaying
    }
}

/// The processes of one app taken together: a browser plays through helper processes of its own.
public struct AudioAppGroup: Equatable, Sendable {
    /// The app's bundle id, or `path:` and the executable for a program that is not an app.
    public let key: String
    /// The app bundle the processes live in, when there is one.
    public let appPath: String?
    /// Sorted, so two readings of the same processes compare equal.
    public let processIDs: [UInt32]
    public let isPlaying: Bool

    public init(key: String, appPath: String?, processIDs: [UInt32], isPlaying: Bool) {
        self.key = key
        self.appPath = appPath
        self.processIDs = processIDs.sorted()
        self.isPlaying = isPlaying
    }
}

/// One line of the mixer's app list.
public struct AudioAppRow: Equatable, Sendable {
    public let key: String
    /// nil for a favorite that is not running.
    public let group: AudioAppGroup?
    public let isFavorite: Bool
    public var isPlaying: Bool { group?.isPlaying ?? false }
    /// Not playing now but heard a moment ago.
    public let isRecent: Bool

    public init(key: String, group: AudioAppGroup?, isFavorite: Bool, isRecent: Bool) {
        self.key = key
        self.group = group
        self.isFavorite = isFavorite
        self.isRecent = isRecent
    }
}

public enum AudioApps {
    /// Processes that play for apps they are not inside of, under the name people know.
    public static let knownNames = ["com.apple.WebKit.GPU": localized("Safari and web views (WebKit)")]

    /// How long an app that went quiet stays in the list.
    public static let recentWindow: TimeInterval = 60

    /// Groups processes by the app they belong to. `bundleIDOfApp` reads an app bundle's id.
    public static func group(_ entries: [AudioProcessEntry], ownPID: Int32, bundleIDOfApp: (String) -> String?) -> [AudioAppGroup] {
        var order: [String] = []
        var members: [String: (appPath: String?, ids: [UInt32], playing: Bool)] = [:]
        for entry in entries where entry.pid != ownPID {
            let appPath = entry.executablePath.flatMap(AppGrouping.appBundle(forExecutable:))
            // Some system processes report an empty bundle id rather than none.
            let bundleID = entry.bundleID.flatMap { $0.isEmpty ? nil : $0 }
            guard let key = appPath.flatMap(bundleIDOfApp) ?? bundleID ?? entry.executablePath.map({ "path:" + $0 }) else { continue }
            if members[key] == nil {
                order.append(key)
                members[key] = (appPath, [], false)
            }
            members[key]?.ids.append(entry.objectID)
            if entry.isPlaying { members[key]?.playing = true }
        }
        return order.compactMap { key in members[key].map { AudioAppGroup(key: key, appPath: $0.appPath, processIDs: $0.ids, isPlaying: $0.playing) } }
    }

    /// Notes the moment each playing app was heard, and forgets the ones quiet for longer than the window.
    public static func remember(_ groups: [AudioAppGroup], in lastHeard: inout [String: Date], now: Date) {
        for group in groups where group.isPlaying { lastHeard[group.key] = now }
        lastHeard = lastHeard.filter { now.timeIntervalSince($0.value) <= recentWindow }
    }

    /// Favorites first in the user's order (also when not running), then the apps playing, then the
    /// ones heard within the window, then running apps that have settings of their own. Within each
    /// part by name.
    public static func rows(groups: [AudioAppGroup], favorites: [String], configured: Set<String>, lastHeard: [String: Date],
                            now: Date, name: (String) -> String) -> [AudioAppRow] {
        let byKey = Dictionary(groups.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
        func isRecent(_ key: String) -> Bool { lastHeard[key].map { now.timeIntervalSince($0) <= recentWindow } ?? false }
        var rows = favorites.map { key in
            AudioAppRow(key: key, group: byKey[key], isFavorite: true, isRecent: !(byKey[key]?.isPlaying ?? false) && isRecent(key))
        }
        let favoriteSet = Set(favorites)
        func rank(_ group: AudioAppGroup) -> Int? {
            if group.isPlaying { return 0 }
            if isRecent(group.key) { return 1 }
            if configured.contains(group.key) { return 2 }
            return nil
        }
        let others = groups
            .filter { !favoriteSet.contains($0.key) }
            .compactMap { group in rank(group).map { (group, $0, name(group.key)) } }
            .sorted { ($0.1, $0.2.localizedLowercase) < ($1.1, $1.2.localizedLowercase) }
        rows += others.map { AudioAppRow(key: $0.0.key, group: $0.0, isFavorite: false, isRecent: $0.1 == 1) }
        return rows
    }
}
