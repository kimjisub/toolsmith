import AppKit
import Combine
import ToolsmithKit

/// What the clipboard shelf shows: the entries, the search, the filter and the selected card.
@MainActor final class ShelfModel: ObservableObject {
    static let pageSize = 60

    private let store: ClipStore
    @Published var query = "" { didSet { if query != oldValue { reload(keepSelection: false) } } }
    /// nil shows every kind.
    @Published var kind: ClipKind? { didSet { if kind != oldValue { reload(keepSelection: false) } } }
    @Published var pinnedOnly = false { didSet { if pinnedOnly != oldValue { reload(keepSelection: false) } } }
    @Published private(set) var items: [ClipItem] = []
    @Published private(set) var selectedID: Int64?
    /// The entry removed last, until something else happens (⌘Z brings it back).
    @Published private(set) var lastDeleted: ClipItem?
    private var reachedEnd = false

    init(store: ClipStore) {
        self.store = store
        reload(keepSelection: false)
    }

    var selected: ClipItem? { items.first { $0.id == selectedID } }

    /// The filters Tab cycles through.
    static let filters: [ClipKind?] = [nil, .text, .image, .link, .file]

    func reload(keepSelection: Bool) {
        // Keeping the selection also keeps how far the list was already loaded.
        let limit = keepSelection ? max(Self.pageSize, items.count) : Self.pageSize
        items = store.items(query: query, kind: kind, pinnedOnly: pinnedOnly, limit: limit, offset: 0)
        reachedEnd = items.count < limit
        if keepSelection, let selectedID, items.contains(where: { $0.id == selectedID }) { return }
        selectedID = items.first?.id
    }

    /// Back to the newest entries, no search, for the next time the shelf opens.
    func reset() {
        endUndo()
        if query.isEmpty, kind == nil, !pinnedOnly {
            reload(keepSelection: false)
        } else {
            // Each assignment reloads; the last one leaves the list right.
            pinnedOnly = false
            kind = nil
            query = ""
        }
    }

    func move(by delta: Int) {
        guard let current = selectedID, let index = items.firstIndex(where: { $0.id == current }) else {
            selectedID = items.first?.id
            return
        }
        let next = min(max(index + delta, 0), items.count - 1)
        selectedID = items[next].id
        if next >= items.count - 8 { loadMore() }
    }

    func select(_ id: Int64) { selectedID = id }

    /// A card near the end came into view (scrolling by trackpad, not by arrow keys).
    func appeared(_ id: Int64) {
        guard let index = items.firstIndex(where: { $0.id == id }), index >= items.count - 8 else { return }
        loadMore()
    }

    private func loadMore() {
        guard !reachedEnd else { return }
        let more = store.items(query: query, kind: kind, pinnedOnly: pinnedOnly, limit: Self.pageSize, offset: items.count)
        reachedEnd = more.count < Self.pageSize
        let known = Set(items.map(\.id))
        items.append(contentsOf: more.filter { !known.contains($0.id) })
    }

    func cycleFilter() {
        let index = Self.filters.firstIndex(of: kind) ?? 0
        kind = Self.filters[(index + 1) % Self.filters.count]
    }

    func togglePin() {
        guard let item = selected else { return }
        store.setPinned(item.id, !item.pinned)
        reload(keepSelection: true)
    }

    func deleteSelected() {
        guard let item = selected, let index = items.firstIndex(of: item) else { return }
        // Only the latest deletion can be undone; the one before it is gone for good, image file included.
        endUndo()
        lastDeleted = store.delete(item.id)
        // Stay where we were: the card that slides into this place becomes the selection.
        let neighbor = items.indices.contains(index + 1) ? items[index + 1].id : (index > 0 ? items[index - 1].id : nil)
        selectedID = neighbor
        reload(keepSelection: true)
    }

    func undoDelete() {
        guard let item = lastDeleted else { return }
        store.restore(item)
        lastDeleted = nil
        reload(keepSelection: true)
        if items.contains(where: { $0.id == item.id }) { selectedID = item.id }
    }

    /// The deletion can no longer be undone: remove its stored image now rather than at the next purge.
    func endUndo() {
        guard lastDeleted != nil else { return }
        lastDeleted = nil
        store.sweepBlobs()
    }

    func item(number: Int) -> ClipItem? {
        number >= 1 && number <= items.count ? items[number - 1] : nil
    }
}
