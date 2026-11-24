import Foundation

/// A way to place the frontmost window.
public enum WindowAction: String, CaseIterable, Sendable {
    case leftHalf = "left-half"
    case rightHalf = "right-half"
    case topHalf = "top-half"
    case bottomHalf = "bottom-half"
    case leftThird = "left-third"
    case centerThird = "center-third"
    case rightThird = "right-third"
    case leftTwoThirds = "left-two-thirds"
    case rightTwoThirds = "right-two-thirds"
    case topLeft = "top-left"
    case topRight = "top-right"
    case bottomLeft = "bottom-left"
    case bottomRight = "bottom-right"
    case maximize
    case center
    case nextDisplay = "next-display"
    case previousDisplay = "previous-display"
    case restore

    /// The command id and the key into the hotkey table.
    public var id: String { "window.\(rawValue)" }

    public var title: String {
        switch self {
        case .leftHalf: return "왼쪽 절반"
        case .rightHalf: return "오른쪽 절반"
        case .topHalf: return "위쪽 절반"
        case .bottomHalf: return "아래쪽 절반"
        case .leftThird: return "왼쪽 3분의 1"
        case .centerThird: return "가운데 3분의 1"
        case .rightThird: return "오른쪽 3분의 1"
        case .leftTwoThirds: return "왼쪽 3분의 2"
        case .rightTwoThirds: return "오른쪽 3분의 2"
        case .topLeft: return "왼쪽 위"
        case .topRight: return "오른쪽 위"
        case .bottomLeft: return "왼쪽 아래"
        case .bottomRight: return "오른쪽 아래"
        case .maximize: return "가득 채우기"
        case .center: return "가운데로"
        case .nextDisplay: return "다음 모니터로 보내기"
        case .previousDisplay: return "이전 모니터로 보내기"
        case .restore: return "이전 크기로 되돌리기"
        }
    }

    /// Words the action is found by besides its title.
    public var keywords: [String] {
        let common = ["창", "화면 나누기", "window"]
        switch self {
        case .leftHalf: return common + ["left half", "좌측 절반", "반 왼쪽"]
        case .rightHalf: return common + ["right half", "우측 절반", "반 오른쪽"]
        case .topHalf: return common + ["top half", "상단 절반"]
        case .bottomHalf: return common + ["bottom half", "하단 절반"]
        case .leftThird: return common + ["left third", "삼분의 일 왼쪽"]
        case .centerThird: return common + ["center third", "삼분의 일 가운데"]
        case .rightThird: return common + ["right third", "삼분의 일 오른쪽"]
        case .leftTwoThirds: return common + ["left two thirds", "삼분의 이 왼쪽"]
        case .rightTwoThirds: return common + ["right two thirds", "삼분의 이 오른쪽"]
        case .topLeft: return common + ["top left", "좌상단", "귀퉁이"]
        case .topRight: return common + ["top right", "우상단", "귀퉁이"]
        case .bottomLeft: return common + ["bottom left", "좌하단", "귀퉁이"]
        case .bottomRight: return common + ["bottom right", "우하단", "귀퉁이"]
        case .maximize: return common + ["maximize", "full", "최대화", "전체"]
        case .center: return common + ["center", "중앙"]
        case .nextDisplay: return common + ["next display", "monitor", "디스플레이", "화면 이동"]
        case .previousDisplay: return common + ["previous display", "monitor", "디스플레이", "화면 이동"]
        case .restore: return common + ["restore", "undo", "원래 크기", "복원"]
        }
    }

    /// An SF Symbol that pictures the placement.
    public var symbol: String {
        switch self {
        case .leftHalf: return "rectangle.lefthalf.filled"
        case .rightHalf: return "rectangle.righthalf.filled"
        case .topHalf: return "rectangle.tophalf.filled"
        case .bottomHalf: return "rectangle.bottomhalf.filled"
        case .leftThird: return "rectangle.leftthird.inset.filled"
        case .centerThird: return "rectangle.center.inset.filled"
        case .rightThird: return "rectangle.rightthird.inset.filled"
        case .leftTwoThirds: return "rectangle.leadinghalf.inset.filled"
        case .rightTwoThirds: return "rectangle.trailinghalf.inset.filled"
        case .topLeft: return "rectangle.inset.topleft.filled"
        case .topRight: return "rectangle.inset.topright.filled"
        case .bottomLeft: return "rectangle.inset.bottomleft.filled"
        case .bottomRight: return "rectangle.inset.bottomright.filled"
        case .maximize: return "rectangle.inset.filled"
        case .center: return "rectangle.portrait.center.inset.filled"
        case .nextDisplay: return "arrow.right.square"
        case .previousDisplay: return "arrow.left.square"
        case .restore: return "arrow.uturn.backward"
        }
    }

    /// Global shortcuts given on first run: the halves, maximize and center, on the keys people
    /// coming from other window managers already know. Everything else runs from the launcher.
    public static let defaultHotkeys: [String: KeyCombo] = {
        let mods: KeyModifiers = [.control, .option]
        return [
            WindowAction.leftHalf.id: KeyCombo(keyCode: 123, modifiers: mods),
            WindowAction.rightHalf.id: KeyCombo(keyCode: 124, modifiers: mods),
            WindowAction.bottomHalf.id: KeyCombo(keyCode: 125, modifiers: mods),
            WindowAction.topHalf.id: KeyCombo(keyCode: 126, modifiers: mods),
            WindowAction.maximize.id: KeyCombo(keyCode: 36, modifiers: mods),
            WindowAction.center.id: KeyCombo(keyCode: 8, modifiers: mods),
        ]
    }()
}
