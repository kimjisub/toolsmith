import Combine
import Foundation

/// What the launcher window shows and does: the typed text, the results, the selected row.
@MainActor public final class LauncherModel: ObservableObject {
    private let engine: LauncherEngine
    private let usage: UsageLog
    private let now: () -> Date

    /// The text in the field, including a Hangul syllable still being composed.
    @Published public var query: String = "" {
        didSet { queryChanged(from: oldValue) }
    }
    /// Whether the field is searching commands, holding a question for the AI, searching only the
    /// snippets, or has given way to the fields of a snippet being filled in.
    public enum Mode: Equatable { case commands, ai, fill, snippets }
    @Published public private(set) var mode: Mode = .commands
    /// The id of the "AI 에게 묻기" row. It is never selected by itself and has no number, so what
    /// the user typed leaves the Mac only after a deliberate step: ↓ or Tab to this row, or a leading ".".
    public static let aiRowID = "ai.ask"

    /// What Return did.
    public enum Submission: Equatable {
        case nothing
        case ran(String)
        /// Send this question to the AI.
        case ask(String)
    }
    /// The snippet being filled in, in `.fill` mode.
    @Published public private(set) var fill: SnippetFill?
    /// How leaving the fill screen, or the snippet search, with esc ends.
    public enum FillExit: Equatable { case backToList, close }
    /// Whether esc in the snippet search goes back to the commands (it was picked there) rather
    /// than closing the launcher (a shortcut opened it).
    public private(set) var snippetSearchReturnsToList = true
    /// The list under the fill screen, which esc there goes back to.
    private var listMode: Mode = .commands
    @Published public private(set) var sections: [ResultSection] = []
    @Published public private(set) var selectedID: String?

    public init(engine: LauncherEngine, usage: UsageLog, now: @escaping () -> Date = Date.init) {
        self.engine = engine
        self.usage = usage
        self.now = now
        recompute(keepSelection: false)
    }

    private var trimmedQuery: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// False while the AI feature is switched off: no "AI 에게 묻기" row, and a leading "." is just a dot.
    public var allowsAI = true {
        didSet {
            guard allowsAI != oldValue else { return }
            if !allowsAI, mode == .ai { mode = .commands }
            recompute(keepSelection: false)
        }
    }

    /// The "AI 에게 묻기" row is offered whenever something is typed in command mode.
    public var showsAIRow: Bool { allowsAI && mode == .commands && !trimmedQuery.isEmpty }

    private func queryChanged(from old: String) {
        guard query != old else { return }
        // A "." typed (or pasted) into the empty field switches to AI; the dot itself is not kept.
        if allowsAI, mode == .commands, old.isEmpty, query.hasPrefix(".") {
            mode = .ai
            query = String(query.dropFirst())
            if query.isEmpty { recompute(keepSelection: false) }
            return
        }
        recompute(keepSelection: false)
    }

    /// Tab: jump to the AI row.
    public func selectAIRow() {
        if showsAIRow { selectedID = Self.aiRowID }
    }

    /// After a question was asked from the AI row: the field now takes follow-up questions.
    public func enterAIMode() {
        mode = .ai
        if query.isEmpty { recompute(keepSelection: false) } else { query = "" }
    }

    public func exitAIMode() {
        guard mode == .ai else { return }
        mode = .commands
        recompute(keepSelection: false)
    }

    // MARK: Searching only the snippets

    /// 「스니펫 검색」: the field starts empty and finds snippets only.
    public func enterSnippetSearch(returnsToList: Bool) {
        fill = nil
        snippetSearchReturnsToList = returnsToList
        mode = .snippets
        if query.isEmpty { recompute(keepSelection: false) } else { query = "" }
    }

    /// Leaves the snippet search: back to the commands when it was picked there; otherwise the
    /// launcher is to close.
    @discardableResult public func exitSnippetSearch() -> FillExit {
        guard mode == .snippets else { return .close }
        mode = .commands
        if query.isEmpty { recompute(keepSelection: false) } else { query = "" }
        return snippetSearchReturnsToList ? .backToList : .close
    }

    /// Return: runs the selected command, or hands back the question for the AI.
    public func submit() -> Submission {
        if mode == .fill { return .nothing }
        if mode == .ai { return trimmedQuery.isEmpty ? .nothing : .ask(trimmedQuery) }
        guard let id = selectedID else { return .nothing }
        if id == Self.aiRowID { return .ask(trimmedQuery) }
        return activate(id: id) ? .ran(id) : .nothing
    }

    /// Command ids in the order they appear on screen.
    public var visibleIDs: [String] { sections.flatMap(\.commandIDs) }

    public func command(id: String) -> Command? { engine.command(id: id) }

    /// Recomputes the results after the commands themselves changed (the app list was rescanned).
    /// The row the user is on stays selected if it is still there.
    public func refresh() {
        recompute(keepSelection: true)
    }

    /// With no results nothing is selected, so Return does nothing.
    private func recompute(keepSelection: Bool) {
        switch mode == .fill ? listMode : mode {
        case .ai: sections = []
        case .snippets:
            sections = engine.results(for: query, in: SnippetCommandSource.section,
                                      excluding: [SnippetCommandSource.searchID], trailing: [SnippetCommandSource.newID])
        case .commands, .fill: sections = engine.results(for: query)
        }
        let ids = visibleIDs
        if keepSelection, let current = selectedID, ids.contains(current) || (current == Self.aiRowID && showsAIRow) { return }
        selectedID = ids.first
    }

    /// Moves the selection, stopping at the first and last rows.
    public func moveSelection(by delta: Int) {
        // The AI row sits below the commands and can be walked to.
        let ids = visibleIDs + (showsAIRow ? [Self.aiRowID] : [])
        guard let current = selectedID, let index = ids.firstIndex(of: current) else {
            if delta > 0 { selectedID = ids.first }
            return
        }
        selectedID = ids[min(max(index + delta, 0), ids.count - 1)]
    }

    public func select(id: String) {
        if visibleIDs.contains(id) { selectedID = id }
    }

    /// Runs the selected command. Returns false when nothing is selected.
    @discardableResult public func activateSelected() -> Bool {
        guard mode != .fill, let id = selectedID, id != Self.aiRowID else { return false }
        return activate(id: id)
    }

    /// Runs the row numbered `number` (1-based, as ⌘1…⌘9 show it).
    @discardableResult public func activate(number: Int) -> Bool {
        let ids = visibleIDs
        guard mode != .fill, number >= 1, number <= ids.count else { return false }
        return activate(id: ids[number - 1])
    }

    @discardableResult public func activate(id: String) -> Bool {
        guard let command = engine.command(id: id) else { return false }
        if command.tracksUsage { usage.record(id, at: now()) }
        command.run()
        return true
    }

    // MARK: Filling in a snippet

    /// Starts filling in a snippet, replacing one already being filled in. The query and the
    /// results stay as they are, for esc to go back to.
    public func beginFill(_ fill: SnippetFill) {
        if mode != .fill { listMode = mode == .snippets ? .snippets : .commands }
        self.fill = fill
        mode = .fill
    }

    public func setFillValue(_ value: String, at index: Int) { fill?.setValue(value, at: index) }

    public func moveFillFocus(by delta: Int) { fill?.moveFocus(by: delta) }

    public func setFillFocus(_ index: Int) { fill?.setFocus(index) }

    /// Leaves the fill screen without pasting. Back to the results when the snippet was picked
    /// there; otherwise the launcher is to close.
    @discardableResult public func cancelFill() -> FillExit {
        guard mode == .fill, let fill else { return .close }
        self.fill = nil
        mode = fill.returnsToList ? listMode : .commands
        return fill.returnsToList ? .backToList : .close
    }

    /// The filled-in text, to paste. This is the moment the snippet counts as used. nil when
    /// nothing is being filled in.
    public func submitFill() -> String? {
        guard mode == .fill, let fill else { return nil }
        usage.record(fill.commandID, at: now())
        self.fill = nil
        mode = .commands
        return fill.text
    }

    /// Back to the empty state, for the next time the window opens.
    public func reset() {
        fill = nil
        mode = .commands
        if query.isEmpty { recompute(keepSelection: false) } else { query = "" }
    }
}
