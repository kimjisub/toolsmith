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

    /// The action's name, from the string catalog. Launcher commands take it as it is, so an action
    /// is found by its English and its Korean name.
    public var titleResource: LocalizedStringResource {
        switch self {
        case .leftHalf: return LocalizedStringResource("Left Half", bundle: .kit)
        case .rightHalf: return LocalizedStringResource("Right Half", bundle: .kit)
        case .topHalf: return LocalizedStringResource("Top Half", bundle: .kit)
        case .bottomHalf: return LocalizedStringResource("Bottom Half", bundle: .kit)
        case .leftThird: return LocalizedStringResource("Left Third", bundle: .kit)
        case .centerThird: return LocalizedStringResource("Center Third", bundle: .kit)
        case .rightThird: return LocalizedStringResource("Right Third", bundle: .kit)
        case .leftTwoThirds: return LocalizedStringResource("Left Two Thirds", bundle: .kit)
        case .rightTwoThirds: return LocalizedStringResource("Right Two Thirds", bundle: .kit)
        case .topLeft: return LocalizedStringResource("Top Left", bundle: .kit)
        case .topRight: return LocalizedStringResource("Top Right", bundle: .kit)
        case .bottomLeft: return LocalizedStringResource("Bottom Left", bundle: .kit)
        case .bottomRight: return LocalizedStringResource("Bottom Right", bundle: .kit)
        case .maximize: return LocalizedStringResource("Maximize", bundle: .kit)
        case .center: return LocalizedStringResource("Center", bundle: .kit)
        case .nextDisplay: return LocalizedStringResource("Move to Next Display", bundle: .kit)
        case .previousDisplay: return LocalizedStringResource("Move to Previous Display", bundle: .kit)
        case .restore: return LocalizedStringResource("Restore Previous Size", bundle: .kit)
        }
    }

    public var title: String { title(locale: .app) }

    public func title(locale: Locale) -> String {
        var resource = titleResource
        resource.locale = locale
        return String(localized: resource)
    }

    /// Words the action is found by besides its title in each language.
    public var keywords: [String] {
        let commonKeywords = ["window", "snap", "창", "화면 나누기"]
        switch self {
        case .leftHalf: return commonKeywords + ["left half", "좌측 절반", "반 왼쪽"]
        case .rightHalf: return commonKeywords + ["right half", "우측 절반", "반 오른쪽"]
        case .topHalf: return commonKeywords + ["top half", "상단 절반"]
        case .bottomHalf: return commonKeywords + ["bottom half", "하단 절반"]
        case .leftThird: return commonKeywords + ["left third", "삼분의 일 왼쪽"]
        case .centerThird: return commonKeywords + ["center third", "삼분의 일 가운데"]
        case .rightThird: return commonKeywords + ["right third", "삼분의 일 오른쪽"]
        case .leftTwoThirds: return commonKeywords + ["left two thirds", "삼분의 이 왼쪽"]
        case .rightTwoThirds: return commonKeywords + ["right two thirds", "삼분의 이 오른쪽"]
        case .topLeft: return commonKeywords + ["top left", "좌상단", "귀퉁이"]
        case .topRight: return commonKeywords + ["top right", "우상단", "귀퉁이"]
        case .bottomLeft: return commonKeywords + ["bottom left", "좌하단", "귀퉁이"]
        case .bottomRight: return commonKeywords + ["bottom right", "우하단", "귀퉁이"]
        case .maximize: return commonKeywords + ["maximize", "full", "최대화", "전체"]
        case .center: return commonKeywords + ["center", "중앙"]
        case .nextDisplay: return commonKeywords + ["next display", "monitor", "디스플레이", "화면 이동"]
        case .previousDisplay: return commonKeywords + ["previous display", "monitor", "디스플레이", "화면 이동"]
        case .restore: return commonKeywords + ["restore", "undo", "원래 크기", "복원"]
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
