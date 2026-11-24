import Foundation

/// Remembers when each command ran, to rank what is used often and recently.
public final class UsageLog {
    /// A use counts half as much every seven days.
    static let halfLife: TimeInterval = 7 * 86_400
    /// Older uses add almost nothing to the score, so only the latest are kept.
    static let keptPerID = 50

    private let fileURL: URL
    /// Use times per command id, oldest first.
    private var uses: [String: [Date]] = [:]

    public init(fileURL: URL) {
        self.fileURL = fileURL
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode([String: [Date]].self, from: data) {
            uses = decoded
        }
    }

    public func record(_ id: String, at date: Date) {
        var times = uses[id, default: []]
        times.append(date)
        uses[id] = Array(times.suffix(Self.keptPerID))
        save()
    }

    /// Forgets a command that no longer exists (a deleted snippet).
    public func remove(_ id: String) {
        guard uses[id] != nil else { return }
        uses[id] = nil
        save()
    }

    /// Sum over uses of 0.5^(age / 7 days): 1.0 for one use right now, 0.5 for one a week ago.
    public func score(_ id: String, now: Date) -> Double {
        (uses[id] ?? []).reduce(0) { total, date in
            total + pow(0.5, max(0, now.timeIntervalSince(date)) / Self.halfLife)
        }
    }

    /// Ids ordered by their latest use, newest first.
    public func recentIDs(limit: Int, now: Date) -> [String] {
        uses.compactMap { id, times in times.last.map { (id, $0) } }
            .sorted { ($0.1, $1.0) > ($1.1, $0.0) }
            .prefix(limit)
            .map(\.0)
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(uses) else { return }
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: fileURL, options: .atomic)
    }
}
