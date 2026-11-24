import Foundation

/// The snippets of this Mac, kept in one JSON file. They never leave the Mac.
public final class SnippetStore {
    private struct File: Codable {
        var schemaVersion = 1
        var snippets: [Snippet]
    }

    private var document: JSONDocument<File>
    private let now: () -> Date
    /// In the order they were made.
    public private(set) var snippets: [Snippet] = []
    /// True when a file was there and could not be read. That file was moved aside
    /// (`snippets.broken.json`) rather than overwritten, so it can be repaired and put back.
    public var loadFailed: Bool { document.loadFailed }
    /// False when a file that could not be read is still in place: writing would replace it.
    private var canWrite: Bool { document.canWrite }

    public init(fileURL: URL, now: @escaping () -> Date = Date.init) {
        document = JSONDocument(fileURL: fileURL)
        self.now = now
        guard let file = document.load(now: now()) else { return }
        // A hand-edited file may repeat an id or hold an entry with nothing in it.
        var seen: Set<UUID> = []
        snippets = file.snippets.filter { Snippet.isValid(name: $0.name, body: $0.body) && seen.insert($0.id).inserted }
    }

    public func snippet(_ id: UUID) -> Snippet? { snippets.first { $0.id == id } }

    /// nil, and nothing changes, when the name or the body is empty.
    @discardableResult public func add(name: String, body: String) -> Snippet? {
        guard canWrite, Snippet.isValid(name: name, body: body) else { return nil }
        let moment = now()
        let snippet = Snippet(id: UUID(), name: name, body: body, createdAt: moment, updatedAt: moment)
        snippets.append(snippet)
        save()
        return snippet
    }

    /// False, and nothing changes, when there is no such snippet or the new name or body is empty.
    @discardableResult public func update(_ id: UUID, name: String, body: String) -> Bool {
        guard canWrite, Snippet.isValid(name: name, body: body), let index = snippets.firstIndex(where: { $0.id == id }) else { return false }
        guard snippets[index].name != name || snippets[index].body != body else { return true }
        snippets[index].name = name
        snippets[index].body = body
        snippets[index].updatedAt = now()
        save()
        return true
    }

    public func remove(_ id: UUID) {
        guard canWrite, snippets.contains(where: { $0.id == id }) else { return }
        snippets.removeAll { $0.id == id }
        save()
    }

    private func save() {
        document.save(File(snippets: snippets))
    }
}
