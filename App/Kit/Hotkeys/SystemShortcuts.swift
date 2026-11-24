import Foundation

/// The shortcuts macOS itself owns (Spotlight, Mission Control, input source switching…),
/// so the settings window can warn when the user picks one of them.
public enum SystemShortcuts {
    // NSEvent.ModifierFlags raw values, as stored in the preference.
    private static let shiftFlag = 1 << 17
    private static let controlFlag = 1 << 18
    private static let optionFlag = 1 << 19
    private static let commandFlag = 1 << 20
    /// Entries without a real key use 65535.
    private static let noKey = 65_535

    /// Parses `AppleSymbolicHotKeys` from the `com.apple.symbolichotkeys` domain.
    /// Each enabled entry carries `value.parameters = [character, key code, modifier flags]`.
    public static func parse(_ symbolicHotKeys: [String: Any]) -> Set<KeyCombo> {
        var combos: Set<KeyCombo> = []
        for entry in symbolicHotKeys.values {
            guard let entry = entry as? [String: Any],
                  entry["enabled"] as? Bool == true,
                  let value = entry["value"] as? [String: Any],
                  let parameters = value["parameters"] as? [Int], parameters.count >= 3,
                  parameters[1] != noKey, let keyCode = UInt16(exactly: parameters[1]) else { continue }
            var modifiers: KeyModifiers = []
            if parameters[2] & shiftFlag != 0 { modifiers.insert(.shift) }
            if parameters[2] & controlFlag != 0 { modifiers.insert(.control) }
            if parameters[2] & optionFlag != 0 { modifiers.insert(.option) }
            if parameters[2] & commandFlag != 0 { modifiers.insert(.command) }
            combos.insert(KeyCombo(keyCode: keyCode, modifiers: modifiers))
        }
        return combos
    }

    public static func current() -> Set<KeyCombo> {
        let value = CFPreferencesCopyAppValue("AppleSymbolicHotKeys" as CFString, "com.apple.symbolichotkeys" as CFString)
        return parse(value as? [String: Any] ?? [:])
    }
}
