import Foundation

/// The pages of the first-run guide.
public enum OnboardingStep: Int, CaseIterable, Sendable {
    case welcome, permissions, tour, ai, privacy, done

    public var next: OnboardingStep { OnboardingStep(rawValue: rawValue + 1) ?? self }
    public var previous: OnboardingStep { OnboardingStep(rawValue: rawValue - 1) ?? self }
    public var isLast: Bool { self == OnboardingStep.allCases.last }
}

/// What the guide's tour page shows: each feature with the key that opens it right now.
public enum OnboardingTour {
    public struct Item: Equatable, Identifiable, Sendable {
        public let title: String
        public let detail: String
        public let symbol: String
        /// The shortcut as currently set; nil when it has none.
        public let keys: String?
        public var id: String { title }
    }

    /// The default shortcuts of the features the tour names, as given on first launch.
    public static let defaultHotkeys: [String: KeyCombo] = WindowAction.defaultHotkeys.merging([
        "clipboard.open": KeyCombo(keyCode: 9, modifiers: [.option]),
        "capture.area": KeyCombo(keyCode: 21, modifiers: [.option, .shift]),
        "capture.screen": KeyCombo(keyCode: 20, modifiers: [.option, .shift]),
    ]) { first, _ in first }

    public static func items(hotkeys: HotkeyTable, locale: Locale = .app) -> [Item] {
        func keys(_ id: String) -> String? { hotkeys.combo(for: id)?.display }
        return [
            Item(title: localized("Window Snapping", locale: locale), detail: localized("Halves, thirds and corners", locale: locale), symbol: "rectangle.lefthalf.filled", keys: keys(WindowAction.leftHalf.id)),
            Item(title: localized("Clipboard History", locale: locale), detail: localized("Find what you copied and paste it again", locale: locale), symbol: "doc.on.clipboard", keys: keys("clipboard.open")),
            Item(title: localized("Screen Capture", locale: locale), detail: localized("Areas, annotations, recording, text recognition", locale: locale), symbol: "camera.viewfinder", keys: keys("capture.area")),
            Item(title: localized("AI Answers", locale: locale), detail: localized("Type a period first in the launcher and ask", locale: locale), symbol: "sparkles", keys: "."),
            Item(title: localized("System Monitor", locale: locale), detail: localized("Click its icon in the menu bar", locale: locale), symbol: "gauge.with.dots.needle.50percent", keys: nil),
            Item(title: localized("Screen Time", locale: locale), detail: localized("How long you used each app", locale: locale), symbol: "hourglass", keys: nil),
        ]
    }
}
