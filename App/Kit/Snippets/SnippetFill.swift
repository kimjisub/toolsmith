import Foundation

/// What the fill screen holds while the user types a snippet's variables. It keeps its own copy of
/// the snippet's text, so what the preview shows is what gets pasted, whatever happens to the
/// snippet meanwhile.
public struct SnippetFill: Equatable {
    /// New for every fill. The screen tells its fields apart by it.
    public let session: UUID
    public let snippetID: UUID
    public let commandID: String
    public let name: String
    public let template: SnippetTemplate
    /// Whether esc goes back to the results the snippet was picked from. False when a global
    /// shortcut opened the fill screen: then esc closes the launcher.
    public let returnsToList: Bool
    /// In the order of `template.variables`. Each starts as its default.
    public private(set) var values: [String]
    public private(set) var focus = 0

    public init(snippet: Snippet, returnsToList: Bool) {
        session = UUID()
        snippetID = snippet.id
        commandID = snippet.commandID
        name = snippet.name
        template = SnippetTemplate(snippet.body)
        self.returnsToList = returnsToList
        values = template.variables.map(\.defaultValue)
    }

    public mutating func setValue(_ value: String, at index: Int) {
        guard values.indices.contains(index) else { return }
        values[index] = value
    }

    /// Past the last field comes the first, and the other way round.
    public mutating func moveFocus(by delta: Int) {
        guard !values.isEmpty else { return }
        focus = ((focus + delta) % values.count + values.count) % values.count
    }

    public mutating func setFocus(_ index: Int) {
        guard values.indices.contains(index) else { return }
        focus = index
    }

    private var valuesByName: [String: String] {
        Dictionary(uniqueKeysWithValues: zip(template.variables.map(\.name), values))
    }

    /// The text to paste.
    public var text: String { template.render(values: valuesByName) }

    public var preview: [SnippetTemplate.Run] { template.preview(values: valuesByName) }
}

public enum SnippetPaste {
    /// ⌘V is pressed only while the app the snippet was meant for is still in front. If the user
    /// switched apps in the moment between, the text stays on the clipboard and nothing is pressed.
    public static func shouldPress(target: pid_t?, frontmost: pid_t?) -> Bool {
        guard let target, let frontmost else { return false }
        return target == frontmost
    }
}
