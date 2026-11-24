import Foundation

/// A piece of text the user wrote ahead of time, to paste into the app in front.
public struct Snippet: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public var name: String
    public var body: String
    public let createdAt: Date
    public var updatedAt: Date

    public init(id: UUID, name: String, body: String, createdAt: Date, updatedAt: Date) {
        self.id = id
        self.name = name
        self.body = body
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public static let commandPrefix = "snippet:"

    /// The snippet's command id, which is also the key of its global shortcut.
    public var commandID: String { Self.commandPrefix + id.uuidString }

    /// A snippet needs a name to be found by and something to paste.
    public static func isValid(name: String, body: String) -> Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// The first line of the body that has something on it.
    public var firstLine: String { lines.first ?? "" }

    /// The body's non-empty lines, trimmed.
    public var lines: [String] {
        body.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}
