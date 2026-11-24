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

    public static func items(hotkeys: HotkeyTable) -> [Item] {
        func keys(_ id: String) -> String? { hotkeys.combo(for: id)?.display }
        return [
            Item(title: "화면 나누기", detail: "창을 절반, 3분의 1, 귀퉁이로", symbol: "rectangle.lefthalf.filled", keys: keys(WindowAction.leftHalf.id)),
            Item(title: "클립보드 기록", detail: "복사했던 것을 찾아 다시 붙이기", symbol: "doc.on.clipboard", keys: keys("clipboard.open")),
            Item(title: "화면 캡처", detail: "영역, 주석, 녹화, 글자 읽기", symbol: "camera.viewfinder", keys: keys("capture.area")),
            Item(title: "AI 검색", detail: "입력창 맨 앞에 점을 치고 묻기", symbol: "sparkles", keys: "."),
            Item(title: "시스템 모니터", detail: "메뉴 막대 아이콘을 누르기", symbol: "gauge.with.dots.needle.50percent", keys: nil),
            Item(title: "사용 시간", detail: "어느 앱을 얼마나 썼는지", symbol: "hourglass", keys: nil),
        ]
    }
}
