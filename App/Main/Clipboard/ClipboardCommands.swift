import AppKit
import ToolsmithKit

/// The clipboard in the launcher: the command that opens the shelf, and the latest copies themselves.
@MainActor final class ClipboardCommandSource: CommandSource {
    static let section = CommandSection(id: "clipboard", title: "클립보드", order: 5)
    static let recentSection = CommandSection(id: "clip-recent", title: "방금 복사한 것", order: 1)
    static let openID = "clipboard.open"
    static let defaultHotkeys: [String: KeyCombo] = [openID: KeyCombo(keyCode: 9, modifiers: [.option])]
    /// How many of the latest copies the launcher can find. The shelf searches all of them.
    static let searchable = 40

    private let store: ClipStore
    var openShelf: () -> Void = {}
    var paste: (ClipItem) -> Void = { _ in }

    init(store: ClipStore) { self.store = store }

    nonisolated func commands() -> [Command] {
        MainActor.assumeIsolated {
            let open = Command(id: Self.openID, title: "클립보드 기록", subtitle: nil,
                               keywords: ["clipboard", "paste", "복사", "붙여넣기", "히스토리"],
                               section: Self.section, icon: .symbol("doc.on.clipboard"), hotkeyID: Self.openID,
                               run: { [weak self] in self?.openShelf() })
            return [open] + latest().map { item in
                Command(id: Self.commandID(item), title: Self.title(of: item),
                        subtitle: [item.sourceName, RelativeTime.text(from: item.copiedAt, now: Date())].compactMap { $0 }.joined(separator: " · "),
                        keywords: [], section: Self.section, icon: .symbol(Self.symbol(of: item)), hotkeyID: nil, tracksUsage: false,
                        run: { [weak self] in self?.paste(item) })
            }
        }
    }

    /// The three newest copies, for the empty launcher.
    nonisolated func emptyStateSections() -> [ResultSection] {
        MainActor.assumeIsolated {
            let ids = latest().prefix(3).map(Self.commandID)
            return ids.isEmpty ? [] : [ResultSection(section: Self.recentSection, commandIDs: Array(ids))]
        }
    }

    private func latest() -> [ClipItem] {
        store.items(query: "", kind: nil, pinnedOnly: false, limit: Self.searchable, offset: 0)
    }

    static func commandID(_ item: ClipItem) -> String { "clip:\(item.id)" }

    static func title(of item: ClipItem) -> String {
        switch item.kind {
        case .text, .link:
            let line = (item.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "\n").first.map(String.init) ?? ""
            return String(line.prefix(80))
        case .image:
            if let width = item.width, let height = item.height { return "이미지 \(width)×\(height)" }
            return "이미지"
        case .file:
            let name = item.fileURLs.first.map { ($0 as NSString).lastPathComponent } ?? "파일"
            return item.fileURLs.count > 1 ? "\(name) 외 \(item.fileURLs.count - 1)개" : name
        }
    }

    static func symbol(of item: ClipItem) -> String {
        switch item.kind {
        case .text: return "text.alignleft"
        case .link: return "link"
        case .image: return "photo"
        case .file: return "doc"
        }
    }
}
