import Foundation

public struct ResultSection: Equatable {
    public let section: CommandSection
    public let commandIDs: [String]

    public init(section: CommandSection, commandIDs: [String]) {
        self.section = section
        self.commandIDs = commandIDs
    }
}

/// Collects commands from every source and answers "what matches this query".
public final class LauncherEngine {
    public static let perSectionLimit = 8
    public static let recentLimit = 6
    public static let recentSection = CommandSection(id: "recent", title: "최근", order: -1)

    /// The sources searched. Set when a feature is switched on or off; `reload()` reads them.
    public var sources: [CommandSource]
    private let usage: UsageLog
    private let now: () -> Date
    /// Sections added to the empty launcher after "최근", besides the sources' own (`CommandSource.emptyStateSections`).
    public var emptyStateExtra: () -> [ResultSection] = { [] }
    private var all: [Command] = []
    private var byID: [String: Command] = [:]

    public init(sources: [CommandSource], usage: UsageLog, now: @escaping () -> Date = Date.init) {
        self.sources = sources
        self.usage = usage
        self.now = now
    }

    /// Reads the commands again from every source. The first command wins when ids collide.
    public func reload() {
        all = []
        byID = [:]
        for command in sources.flatMap({ $0.commands() }) where byID[command.id] == nil {
            byID[command.id] = command
            all.append(command)
        }
    }

    public func command(id: String) -> Command? { byID[id] }

    /// The command a global shortcut runs.
    public func command(hotkeyID: String) -> Command? {
        all.first { $0.hotkeyID == hotkeyID }
    }

    /// Every command that can be given a global shortcut, in source order.
    public func hotkeyCommands() -> [Command] {
        all.filter { $0.hotkeyID != nil }
    }

    /// Matching commands grouped by section. An empty query shows what was used most recently.
    public func results(for query: String) -> [ResultSection] {
        let moment = now()
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else {
            // Ask for more than we show: some remembered commands may be gone (an uninstalled app).
            let ids = usage.recentIDs(limit: Self.recentLimit * 4, now: moment).filter { byID[$0] != nil }
            var sections = ids.isEmpty ? [] : [ResultSection(section: Self.recentSection, commandIDs: Array(ids.prefix(Self.recentLimit)))]
            for extra in sources.flatMap({ $0.emptyStateSections() }) + emptyStateExtra() {
                let known = extra.commandIDs.filter { byID[$0] != nil }
                if !known.isEmpty { sections.append(ResultSection(section: extra.section, commandIDs: known)) }
            }
            return sections
        }

        // The section holding the best match comes first, so Return runs what was typed (an app's
        // name) rather than whatever a fixed section order happens to put on top.
        return matches(for: query, among: all, at: moment)
            .sorted { left, right in
                if let a = left.value.first, let b = right.value.first {
                    if a.score.kind != b.score.kind { return a.score.kind < b.score.kind }
                    if a.viaKeyword != b.viaKeyword { return !a.viaKeyword }
                }
                return (left.key.order, left.key.title) < (right.key.order, right.key.title)
            }
            .map { section, hits in ResultSection(section: section, commandIDs: hits.prefix(Self.perSectionLimit).map(\.command.id)) }
    }

    /// The commands of one section only, all of them: nothing else is on screen to make room for.
    /// An empty query lists the whole section, what is used most first, with `trailing` at the end.
    public func results(for query: String, in section: CommandSection, excluding: Set<String>, trailing: Set<String>) -> [ResultSection] {
        let moment = now()
        let scoped = all.filter { $0.section == section && !excluding.contains($0.id) }
        let ids: [String]
        if query.trimmingCharacters(in: .whitespaces).isEmpty {
            ids = scoped.enumerated().sorted { left, right in
                let (leftLast, rightLast) = (trailing.contains(left.element.id), trailing.contains(right.element.id))
                if leftLast != rightLast { return rightLast }
                let (leftUsage, rightUsage) = (usage.score(left.element.id, now: moment), usage.score(right.element.id, now: moment))
                if !leftLast, leftUsage != rightUsage { return leftUsage > rightUsage }
                return left.offset < right.offset
            }.map(\.element.id)
        } else {
            ids = (matches(for: query, among: scoped, at: moment)[section] ?? []).map(\.command.id)
        }
        return ids.isEmpty ? [] : [ResultSection(section: section, commandIDs: ids)]
    }

    /// A matching command. `viaKeyword` breaks ties: at the same match kind, a hit on the title
    /// outranks a hit on a keyword.
    private struct Hit { let command: Command; let score: MatchScore; let viaKeyword: Bool; let usage: Double; let index: Int }

    /// The commands that match, best first, under their sections.
    private func matches(for query: String, among commands: [Command], at moment: Date) -> [CommandSection: [Hit]] {
        var bySection: [CommandSection: [Hit]] = [:]
        for (index, command) in commands.enumerated() {
            let title = Matcher.score(query: query, candidate: command.title)
            // A keyword must be hit from the start of a word: its middle letters ("te" in "center") are noise.
            let keyword = command.keywords.compactMap { Matcher.score(query: query, candidate: $0) }.filter { $0.kind != .substring }.min()
            let viaKeyword: Bool
            let best: MatchScore
            switch (title, keyword) {
            case (nil, nil): continue
            case (let title?, nil): (best, viaKeyword) = (title, false)
            case (nil, let keyword?): (best, viaKeyword) = (keyword, true)
            case (let title?, let keyword?): (best, viaKeyword) = keyword.kind < title.kind ? (keyword, true) : (title, false)
            }
            bySection[command.section, default: []].append(
                Hit(command: command, score: best, viaKeyword: viaKeyword, usage: usage.score(command.id, now: moment), index: index))
        }
        return bySection.mapValues { hits in
            // Better match kind, then title over keyword, then position, then what is used more, then source order.
            hits.sorted {
                if $0.score.kind != $1.score.kind { return $0.score.kind < $1.score.kind }
                if $0.viaKeyword != $1.viaKeyword { return !$0.viaKeyword }
                if $0.score.position != $1.score.position { return $0.score.position < $1.score.position }
                if $0.usage != $1.usage { return $0.usage > $1.usage }
                return $0.index < $1.index
            }
        }
    }
}
