import CryptoKit
import Foundation
import SQLite3

/// The clipboard history on disk: a SQLite file plus one file per stored image.
/// Lives in one folder on this Mac and is sent nowhere. Use from one thread (the main thread).
public final class ClipStore {
    public enum StoreError: Error { case open(String), empty, write(String) }

    /// Only the start of a long text is searchable; enough to find it, bounded for speed.
    static let searchableCharacters = 4_000

    private var db: OpaquePointer?
    private let blobs: URL
    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    public init(directory: URL) throws {
        blobs = directory.appendingPathComponent("blobs", isDirectory: true)
        try FileManager.default.createDirectory(at: blobs, withIntermediateDirectories: true)
        let path = directory.appendingPathComponent("clipboard.sqlite").path
        guard sqlite3_open_v2(path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else {
            throw StoreError.open(String(cString: sqlite3_errmsg(db)))
        }
        try execute("PRAGMA journal_mode = WAL")
        // Deleted entries are overwritten on disk, not just unlinked from the file's index.
        try execute("PRAGMA secure_delete = ON")
        try execute("""
            CREATE TABLE IF NOT EXISTS items(
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                kind TEXT NOT NULL, text TEXT, search TEXT NOT NULL, files TEXT, blob TEXT,
                bytes INTEGER NOT NULL, width INTEGER, height INTEGER,
                source_id TEXT, source_name TEXT,
                copied_at REAL NOT NULL, pinned INTEGER NOT NULL DEFAULT 0, hash TEXT NOT NULL UNIQUE)
            """)
        try execute("CREATE INDEX IF NOT EXISTS items_copied_at ON items(copied_at DESC)")
    }

    deinit { sqlite3_close(db) }

    // MARK: Writing

    /// Stores a copy. Copying the same content again moves the existing entry to the front.
    @discardableResult public func record(_ draft: ClipDraft, at date: Date) throws -> ClipItem {
        let content: Data
        switch draft.kind {
        case .text, .link:
            guard let text = draft.text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw StoreError.empty }
            content = Data(text.utf8)
        case .image:
            guard let data = draft.data, !data.isEmpty else { throw StoreError.empty }
            content = data
        case .file:
            guard !draft.fileURLs.isEmpty else { throw StoreError.empty }
            content = Data(draft.fileURLs.joined(separator: "\n").utf8)
        }
        let hash = SHA256.hash(data: Data(draft.kind.rawValue.utf8) + [0] + content).map { String(format: "%02x", $0) }.joined()

        if let existing = first("SELECT * FROM items WHERE hash = ?", [hash]) {
            run("UPDATE items SET copied_at = ?, source_id = ?, source_name = ? WHERE id = ?",
                [date.timeIntervalSince1970, draft.sourceBundleID, draft.sourceName, existing.id])
            return first("SELECT * FROM items WHERE id = ?", [existing.id]) ?? existing
        }

        // The image itself, or the formatted form (RTF) of a text, is kept as a file beside the database.
        var blobName: String?
        if let blob = draft.kind == .image ? content : draft.data, !blob.isEmpty {
            blobName = "\(hash).bin"
            do { try blob.write(to: blobs.appendingPathComponent(blobName!), options: .atomic) } catch { throw StoreError.write(error.localizedDescription) }
        }
        let files = draft.fileURLs.isEmpty ? nil : draft.fileURLs.joined(separator: "\n")
        run("""
            INSERT INTO items(kind, text, search, files, blob, bytes, width, height, source_id, source_name, copied_at, pinned, hash)
            VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 0, ?)
            """,
            [draft.kind.rawValue, draft.text, Self.searchText(text: draft.text, files: draft.fileURLs, source: draft.sourceName), files, blobName,
             content.count, draft.width, draft.height, draft.sourceBundleID, draft.sourceName, date.timeIntervalSince1970, hash])
        guard let item = first("SELECT * FROM items WHERE hash = ?", [hash]) else { throw StoreError.write(lastError) }
        return item
    }

    public func setPinned(_ id: Int64, _ pinned: Bool) {
        run("UPDATE items SET pinned = ? WHERE id = ?", [pinned ? 1 : 0, id])
    }

    /// Moves an entry to the front (it was just pasted).
    public func touch(_ id: Int64, at date: Date) {
        run("UPDATE items SET copied_at = ? WHERE id = ?", [date.timeIntervalSince1970, id])
    }

    /// Removes an entry and returns it, so the removal can be undone with `restore`.
    /// A stored image stays on disk until `sweepBlobs`.
    @discardableResult public func delete(_ id: Int64) -> ClipItem? {
        guard let item = first("SELECT * FROM items WHERE id = ?", [id]) else { return nil }
        run("DELETE FROM items WHERE id = ?", [id])
        return item
    }

    /// Puts back an entry removed by `delete`, with its id, time and pin.
    public func restore(_ item: ClipItem) {
        let files = item.fileURLs.isEmpty ? nil : item.fileURLs.joined(separator: "\n")
        run("""
            INSERT OR IGNORE INTO items(id, kind, text, search, files, blob, bytes, width, height, source_id, source_name, copied_at, pinned, hash)
            VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            [item.id, item.kind.rawValue, item.text, Self.searchText(text: item.text, files: item.fileURLs, source: item.sourceName), files, item.blobName,
             item.bytes, item.width, item.height, item.sourceBundleID, item.sourceName, item.copiedAt.timeIntervalSince1970, item.pinned ? 1 : 0, item.hash])
    }

    /// Removes unpinned entries copied before `date`. Returns how many.
    @discardableResult public func purge(olderThan date: Date) -> Int {
        run("DELETE FROM items WHERE pinned = 0 AND copied_at < ?", [date.timeIntervalSince1970])
        let removed = Int(sqlite3_changes(db))
        if removed > 0 { sweepBlobs() }
        return removed
    }

    public func clearAll(keepPinned: Bool) {
        run(keepPinned ? "DELETE FROM items WHERE pinned = 0" : "DELETE FROM items", [])
        // The write-ahead log still holds the old pages; fold it into the (now overwritten) file and empty it.
        run("PRAGMA wal_checkpoint(TRUNCATE)", [])
    }

    /// Deletes stored images no entry refers to any more. Returns how many files were removed.
    @discardableResult public func sweepBlobs() -> Int {
        // If the list of files in use cannot be read, delete nothing: an empty answer here would
        // mean "no file is in use" and take every stored image with it.
        guard let check = prepare("SELECT blob FROM items WHERE blob IS NOT NULL", []) else { return 0 }
        var used: Set<String> = []
        while sqlite3_step(check) == SQLITE_ROW {
            if let text = sqlite3_column_text(check, 0) { used.insert(String(cString: text)) }
        }
        sqlite3_finalize(check)
        let files = (try? FileManager.default.contentsOfDirectory(atPath: blobs.path)) ?? []
        var removed = 0
        for file in files where !used.contains(file) {
            if (try? FileManager.default.removeItem(at: blobs.appendingPathComponent(file))) != nil { removed += 1 }
        }
        return removed
    }

    // MARK: Reading

    /// Entries newest first. `query` is matched against the text, file names and source app,
    /// by typed letters, so a Hangul syllable still being composed matches.
    public func items(query: String, kind: ClipKind?, pinnedOnly: Bool, limit: Int, offset: Int) -> [ClipItem] {
        var conditions: [String] = []
        var values: [Any?] = []
        let needle = HangulText.jamo(query.trimmingCharacters(in: .whitespacesAndNewlines))
        if !needle.isEmpty {
            // instr, not LIKE: the query is plain text, % and _ mean themselves.
            conditions.append("instr(search, ?) > 0")
            values.append(needle)
        }
        if let kind {
            conditions.append("kind = ?")
            values.append(kind.rawValue)
        }
        if pinnedOnly { conditions.append("pinned = 1") }
        let filter = conditions.isEmpty ? "" : "WHERE " + conditions.joined(separator: " AND ")
        return all("SELECT * FROM items \(filter) ORDER BY copied_at DESC, id DESC LIMIT ? OFFSET ?", values + [limit, offset])
    }

    public func item(id: Int64) -> ClipItem? { first("SELECT * FROM items WHERE id = ?", [id]) }

    public func stats() -> (count: Int, bytes: Int) {
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(db, "SELECT COUNT(*), COALESCE(SUM(bytes), 0) FROM items", -1, &statement, nil) == SQLITE_OK,
              sqlite3_step(statement) == SQLITE_ROW else { return (0, 0) }
        return (Int(sqlite3_column_int64(statement, 0)), Int(sqlite3_column_int64(statement, 1)))
    }

    public func blobURL(for item: ClipItem) -> URL? {
        item.blobName.map { blobs.appendingPathComponent($0) }
    }

    // MARK: SQLite

    static func searchText(text: String?, files: [String], source: String?) -> String {
        var parts: [String] = []
        if let text { parts.append(String(text.prefix(searchableCharacters))) }
        parts.append(contentsOf: files.map { ($0 as NSString).lastPathComponent })
        if let source { parts.append(source) }
        return HangulText.jamo(parts.joined(separator: "\n"))
    }

    private var lastError: String { String(cString: sqlite3_errmsg(db)) }

    private func execute(_ sql: String) throws {
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else { throw StoreError.open(lastError) }
    }

    private func prepare(_ sql: String, _ values: [Any?]) -> OpaquePointer? {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return nil }
        for (index, value) in values.enumerated() {
            let position = Int32(index + 1)
            switch value {
            case nil: sqlite3_bind_null(statement, position)
            case let value as String: sqlite3_bind_text(statement, position, value, -1, Self.transient)
            case let value as Int: sqlite3_bind_int64(statement, position, Int64(value))
            case let value as Int64: sqlite3_bind_int64(statement, position, value)
            case let value as Double: sqlite3_bind_double(statement, position, value)
            default: sqlite3_bind_null(statement, position)
            }
        }
        return statement
    }

    private func run(_ sql: String, _ values: [Any?]) {
        let statement = prepare(sql, values)
        defer { sqlite3_finalize(statement) }
        sqlite3_step(statement)
    }

    private func first(_ sql: String, _ values: [Any?]) -> ClipItem? { all(sql, values).first }

    private func all(_ sql: String, _ values: [Any?]) -> [ClipItem] {
        guard let statement = prepare(sql, values) else { return [] }
        defer { sqlite3_finalize(statement) }
        var columns: [String: Int32] = [:]
        for index in 0..<sqlite3_column_count(statement) { columns[String(cString: sqlite3_column_name(statement, index))] = index }
        func string(_ name: String) -> String? {
            guard let index = columns[name], sqlite3_column_type(statement, index) != SQLITE_NULL, let text = sqlite3_column_text(statement, index) else { return nil }
            return String(cString: text)
        }
        func int(_ name: String) -> Int? {
            guard let index = columns[name], sqlite3_column_type(statement, index) != SQLITE_NULL else { return nil }
            return Int(sqlite3_column_int64(statement, index))
        }
        var items: [ClipItem] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let id = int("id"), let kind = string("kind").flatMap(ClipKind.init(rawValue:)), let hash = string("hash"),
                  let copiedIndex = columns["copied_at"] else { continue }
            items.append(ClipItem(
                id: Int64(id), kind: kind, text: string("text"),
                fileURLs: string("files")?.components(separatedBy: "\n") ?? [],
                blobName: string("blob"), bytes: int("bytes") ?? 0, width: int("width"), height: int("height"),
                sourceBundleID: string("source_id"), sourceName: string("source_name"),
                copiedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, copiedIndex)),
                pinned: (int("pinned") ?? 0) != 0, hash: hash))
        }
        return items
    }
}
