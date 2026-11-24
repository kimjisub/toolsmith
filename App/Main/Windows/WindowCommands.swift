import AppKit
import ToolsmithKit

/// The window placements as launcher commands.
@MainActor final class WindowCommandSource: CommandSource {
    static let section = CommandSection(id: "window", title: "화면 나누기", order: 0)
    private let mover = WindowMover()
    /// The app whose window an action moves: the one in front when the launcher opened, or when a shortcut fired.
    var target: () -> NSRunningApplication? = { nil }
    var gap: () -> CGFloat = { 0 }
    /// Called with one line to show when an action could not be done.
    var onFailure: (String) -> Void = { _ in }

    nonisolated func commands() -> [Command] {
        MainActor.assumeIsolated {
            WindowAction.allCases.map { action in
                Command(id: action.id, title: action.title, subtitle: nil, keywords: action.keywords, section: Self.section,
                        icon: .symbol(action.symbol), hotkeyID: action.id,
                        run: { [weak self] in self?.run(action) })
            }
        }
    }

    private func run(_ action: WindowAction) {
        if case .failure(let failure) = mover.perform(action, on: target(), gap: gap()) {
            onFailure(failure.message)
        }
    }
}
