import Foundation

/// A snippet's text taken apart: plain text and the variables the user is asked for.
///
/// The text is read once, left to right:
/// 1. `{{` is a literal `{` and `}}` a literal `}`.
/// 2. A `{` up to the first `}` on the same line is a placeholder, unless another `{` comes first.
/// 3. Inside it, what is before the first `:` is the name (trimmed) and what is after is the default.
/// 4. Anything else, including a `{` that is never closed, stays as typed.
public struct SnippetTemplate: Equatable {
    public enum Piece: Equatable {
        case text(String)
        case variable(String)
    }

    public struct Variable: Equatable {
        public let name: String
        public let defaultValue: String

        public init(name: String, defaultValue: String) {
            self.name = name
            self.defaultValue = defaultValue
        }
    }

    /// One stretch of the preview: plain text, a value the user typed (`.filled`), or a variable
    /// still empty (`.pending`, where `text` is its name).
    public struct Run: Equatable {
        public enum Kind: Equatable { case plain, filled, pending }
        public let text: String
        public let kind: Kind

        public init(text: String, kind: Kind) {
            self.text = text
            self.kind = kind
        }
    }

    public let pieces: [Piece]
    /// The variables to ask for, in the order they first appear. A name appears once.
    public let variables: [Variable]

    public init(_ body: String) {
        var pieces: [Piece] = []
        var variables: [Variable] = []
        var text = ""

        func flush() {
            if !text.isEmpty { pieces.append(.text(text)) }
            text = ""
        }

        let characters = Array(body)
        var index = 0
        while index < characters.count {
            let character = characters[index]
            let next: Character? = index + 1 < characters.count ? characters[index + 1] : nil
            if (character == "{" && next == "{") || (character == "}" && next == "}") {
                text.append(character)
                index += 2
                continue
            }
            if character == "{", let close = Self.placeholderEnd(in: characters, after: index),
               let parsed = Self.parse(String(characters[(index + 1)..<close])) {
                flush()
                pieces.append(.variable(parsed.name))
                if !variables.contains(where: { $0.name == parsed.name }) { variables.append(parsed) }
                index = close + 1
                continue
            }
            text.append(character)
            index += 1
        }
        flush()

        self.pieces = pieces
        self.variables = variables
    }

    /// The index of the `}` that closes the `{` at `open`, when nothing else gets in the way first.
    private static func placeholderEnd(in characters: [Character], after open: Int) -> Int? {
        var index = open + 1
        while index < characters.count {
            let character = characters[index]
            if character == "}" { return index }
            if character == "{" || character.isNewline { return nil }
            index += 1
        }
        return nil
    }

    /// nil when the name is empty: then the braces are just text.
    private static func parse(_ inside: String) -> Variable? {
        let parts = inside.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        let name = (parts.first.map(String.init) ?? "").trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return nil }
        return Variable(name: name, defaultValue: parts.count > 1 ? String(parts[1]) : "")
    }

    /// The finished text. A variable missing from `values` is empty. Values go in as they are:
    /// braces inside a value are not read again.
    public func render(values: [String: String]) -> String {
        pieces.map { piece in
            switch piece {
            case .text(let text): return text
            case .variable(let name): return values[name] ?? ""
            }
        }.joined()
    }

    /// The text as the fill screen shows it: an empty variable shows its name, marked `.pending`.
    public func preview(values: [String: String]) -> [Run] {
        pieces.map { piece in
            switch piece {
            case .text(let text):
                return Run(text: text, kind: .plain)
            case .variable(let name):
                let value = values[name] ?? ""
                return value.isEmpty ? Run(text: name, kind: .pending) : Run(text: value, kind: .filled)
            }
        }
    }
}
