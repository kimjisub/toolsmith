import Foundation

/// Which menu bar items show, in what order (left to right) and how. The saved list may name items
/// of modules that are off right now: they keep their place for when the module comes back.
public struct MenuBarLayout: Codable, Equatable, Sendable {
    public struct Entry: Codable, Equatable, Sendable {
        public let id: String
        public var visible: Bool
        /// nil when the saved style is unknown (a newer version wrote it): the item's default applies.
        public var style: MenuBarStyle?

        public init(id: String, visible: Bool, style: MenuBarStyle?) {
            self.id = id
            self.visible = visible
            self.style = style
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decode(String.self, forKey: .id)
            visible = try container.decodeIfPresent(Bool.self, forKey: .visible) ?? false
            style = (try? container.decodeIfPresent(String.self, forKey: .style)).flatMap { $0.flatMap(MenuBarStyle.init(rawValue:)) }
        }
    }

    /// An item as the menu bar and the settings see it.
    public struct Item: Equatable, Sendable {
        public let descriptor: MenuBarItemDescriptor
        public let visible: Bool
        public let style: MenuBarStyle
        public var id: String { descriptor.id }
    }

    public private(set) var entries: [Entry]
    /// True: every item is drawn inside one menu bar slot. False: each item gets its own.
    public var combined: Bool

    public init(entries: [Entry] = [], combined: Bool = true) {
        self.entries = entries
        self.combined = combined
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        entries = (try? container.decodeIfPresent([Entry].self, forKey: .entries)) ?? []
        combined = try container.decodeIfPresent(Bool.self, forKey: .combined) ?? true
    }

    /// Every available item in the user's order. One never placed before comes after the others, as its module declares it.
    public func items(_ available: [MenuBarItemDescriptor]) -> [Item] {
        let byID = Dictionary(available.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var seen: Set<String> = []
        var result: [Item] = []
        for entry in entries {
            guard let descriptor = byID[entry.id], seen.insert(entry.id).inserted else { continue }
            let style = entry.style.flatMap { descriptor.styles.contains($0) ? $0 : nil } ?? descriptor.defaultStyle
            result.append(Item(descriptor: descriptor, visible: entry.visible, style: style))
        }
        for descriptor in available where seen.insert(descriptor.id).inserted {
            result.append(Item(descriptor: descriptor, visible: descriptor.defaultVisible, style: descriptor.defaultStyle))
        }
        return result
    }

    /// What the menu bar draws: the visible items, or the app icon alone when none is, so the app
    /// can always be reached.
    public func shown(_ available: [MenuBarItemDescriptor]) -> [Item] {
        let visible = items(available).filter(\.visible)
        if !visible.isEmpty { return visible }
        let icon = available.first { $0.id == MenuBarItemDescriptor.appIcon.id } ?? .appIcon
        return [Item(descriptor: icon, visible: true, style: .icon)]
    }

    public mutating func setVisible(_ id: String, _ visible: Bool, among available: [MenuBarItemDescriptor]) {
        edit(id, among: available) { $0.visible = visible }
    }

    public mutating func setStyle(_ id: String, _ style: MenuBarStyle, among available: [MenuBarItemDescriptor]) {
        guard available.first(where: { $0.id == id })?.styles.contains(style) == true else { return }
        edit(id, among: available) { $0.style = style }
    }

    /// Moves items of the list `items(available)` shows, as a drag in that list does. Saved items
    /// of modules that are off keep their places.
    public mutating func move(fromOffsets source: IndexSet, toOffset destination: Int, among available: [MenuBarItemDescriptor]) {
        materialize(available)
        let availableIDs = Set(available.map(\.id))
        let slots = entries.indices.filter { availableIDs.contains(entries[$0].id) }
        var subset = slots.map { entries[$0] }
        let valid = source.filter { $0 < subset.count }
        guard !valid.isEmpty else { return }
        let moving = valid.map { subset[$0] }
        subset = subset.enumerated().filter { !valid.contains($0.offset) }.map(\.element)
        let target = min(max(destination - valid.filter { $0 < destination }.count, 0), subset.count)
        subset.insert(contentsOf: moving, at: target)
        for (slot, entry) in zip(slots, subset) { entries[slot] = entry }
    }

    private mutating func edit(_ id: String, among available: [MenuBarItemDescriptor], _ change: (inout Entry) -> Void) {
        materialize(available)
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        change(&entries[index])
    }

    /// Writes down every available item at its current state, so an edit fixes the order the user saw.
    private mutating func materialize(_ available: [MenuBarItemDescriptor]) {
        let shownItems = items(available)
        var known = Set(entries.map(\.id))
        for item in shownItems where known.insert(item.id).inserted {
            entries.append(Entry(id: item.id, visible: item.visible, style: item.style))
        }
        // Duplicates in a hand-edited file: the first one counts.
        var seen: Set<String> = []
        entries = entries.filter { seen.insert($0.id).inserted }
    }
}

extension MenuBarLayout {
    /// The meters of the settings before modules (schema 1), in their fixed order.
    static let legacyMeters = ["cpu", "memory", "disk", "network", "battery"]

    /// The menu bar of a schema 1 settings file, drawn the same way: the chosen meters as graphs
    /// in their order, the temperature and power readout at the end, the mark only when nothing is chosen.
    public static func legacy(meters: [String], readout: Bool) -> MenuBarLayout {
        let chosen = legacyMeters.filter(meters.contains)
        var entries = chosen.map { Entry(id: "monitor.\($0)", visible: true, style: .graph) }
        entries += legacyMeters.filter { !chosen.contains($0) }.map { Entry(id: "monitor.\($0)", visible: false, style: .graph) }
        entries.append(Entry(id: "monitor.readout", visible: readout, style: .value))
        entries.append(Entry(id: MenuBarItemDescriptor.appIcon.id, visible: false, style: .icon))
        return MenuBarLayout(entries: entries, combined: true)
    }
}
