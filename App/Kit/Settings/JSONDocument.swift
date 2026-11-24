import Foundation

/// A value kept in one JSON file of its own. A file that is there but cannot be read is never
/// written over: it is moved aside (`<name>.broken.json`) so it can be repaired and put back, and
/// when even that fails nothing is written at all.
public struct JSONDocument<Value: Codable> {
    public let fileURL: URL
    /// True when a file was there and could not be read.
    public private(set) var loadFailed = false
    /// False when a file that could not be read is still in place.
    public private(set) var canWrite = true

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    /// nil for no file (the ordinary first run) and for a file that could not be read.
    public mutating func load(now: Date = Date()) -> Value? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let data = try? Data(contentsOf: fileURL), let value = try? decoder.decode(Value.self, from: data) { return value }
        loadFailed = true
        canWrite = moveAside(now: now)
        return nil
    }

    public func save(_ value: Value) {
        guard canWrite else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(value) else { return }
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: fileURL, options: .atomic)
    }

    /// False when the file could not be moved.
    private func moveAside(now: Date) -> Bool {
        let directory = fileURL.deletingLastPathComponent()
        let stem = fileURL.deletingPathExtension().lastPathComponent
        var aside = directory.appendingPathComponent("\(stem).broken.json")
        if FileManager.default.fileExists(atPath: aside.path) {
            aside = directory.appendingPathComponent("\(stem).broken-\(Int(now.timeIntervalSince1970)).json")
        }
        return (try? FileManager.default.moveItem(at: fileURL, to: aside)) != nil
    }
}
