import Foundation

/// The snippets in the launcher: one command to search only them, one per snippet, and one to
/// make a new snippet.
public final class SnippetCommandSource: CommandSource {
    public static let section = CommandSection(id: "snippets", title: localized("Snippets"), order: 4)
    public static let newID = "snippets.new"
    public static let searchID = "snippets.search"
    /// How many lines of a snippet's text it can be found by.
    static let searchableLines = 5

    private let store: SnippetStore
    /// A snippet with nothing to ask was picked: paste it.
    public var onInsert: @MainActor (Snippet, SnippetTemplate) -> Void = { _, _ in }
    /// A snippet with variables was picked: open the fill screen.
    public var onFill: @MainActor (Snippet) -> Void = { _ in }
    public var onNew: @MainActor () -> Void = {}
    /// Search Snippets was run: the launcher goes on to show only snippets.
    public var onSearch: @MainActor () -> Void = {}

    public init(store: SnippetStore) { self.store = store }

    public func commands() -> [Command] {
        let snippets = store.snippets.map { snippet -> Command in
            let template = SnippetTemplate(snippet.body)
            let asks = !template.variables.isEmpty
            // A snippet that asks counts as used when it is pasted, not when its fields open.
            return Command(id: snippet.commandID, title: snippet.name, subtitle: snippet.firstLine,
                           keywords: Array(snippet.lines.prefix(Self.searchableLines)), section: Self.section,
                           icon: .symbol("text.quote"), hotkeyID: snippet.commandID,
                           tracksUsage: !asks, keepsLauncherOpen: asks,
                           run: { [weak self] in
                               if asks { self?.onFill(snippet) } else { self?.onInsert(snippet, template) }
                           })
        }
        let new = Command(id: Self.newID, localizedTitle: LocalizedStringResource("New Snippet", bundle: .kit), subtitle: nil,
                          keywords: ["snippet", "멘트", "문구", "상용구"], section: Self.section,
                          icon: .symbol("plus.bubble"), hotkeyID: nil,
                          run: { [weak self] in self?.onNew() })
        let search = Command(id: Self.searchID, localizedTitle: LocalizedStringResource("Search Snippets", bundle: .kit), subtitle: nil,
                             keywords: ["snippet", "멘트", "문구", "상용구"], section: Self.section,
                             icon: .symbol("text.magnifyingglass"), hotkeyID: Self.searchID, keepsLauncherOpen: true,
                             run: { [weak self] in self?.onSearch() })
        return [search] + snippets + [new]
    }
}
