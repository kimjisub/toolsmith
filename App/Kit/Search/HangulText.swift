import Foundation

/// Breaks Hangul into the letters a person types, so a half-composed syllable still matches.
///
/// "왼" is typed ㅇ, ㅗ, ㅣ, ㄴ and shows on screen as ㅇ → 오 → 외 → 왼. Comparing letter
/// sequences makes each of those a prefix of "왼쪽".
public enum HangulText {
    private static let initials = ["ㄱ", "ㄲ", "ㄴ", "ㄷ", "ㄸ", "ㄹ", "ㅁ", "ㅂ", "ㅃ", "ㅅ", "ㅆ", "ㅇ", "ㅈ", "ㅉ", "ㅊ", "ㅋ", "ㅌ", "ㅍ", "ㅎ"]
    /// Compound vowels are spelled out as the keys pressed.
    private static let medials = ["ㅏ", "ㅐ", "ㅑ", "ㅒ", "ㅓ", "ㅔ", "ㅕ", "ㅖ", "ㅗ", "ㅗㅏ", "ㅗㅐ", "ㅗㅣ", "ㅛ", "ㅜ", "ㅜㅓ", "ㅜㅔ", "ㅜㅣ", "ㅠ", "ㅡ", "ㅡㅣ", "ㅣ"]
    /// Compound finals too. Double consonants (ㄲ, ㅆ) are one key and stay whole.
    private static let finals = ["", "ㄱ", "ㄲ", "ㄱㅅ", "ㄴ", "ㄴㅈ", "ㄴㅎ", "ㄷ", "ㄹ", "ㄹㄱ", "ㄹㅁ", "ㄹㅂ", "ㄹㅅ", "ㄹㅌ", "ㄹㅍ", "ㄹㅎ", "ㅁ", "ㅂ", "ㅂㅅ", "ㅅ", "ㅆ", "ㅇ", "ㅈ", "ㅊ", "ㅋ", "ㅌ", "ㅍ", "ㅎ"]
    private static let standaloneCompounds: [Character: String] = [
        "ㅘ": "ㅗㅏ", "ㅙ": "ㅗㅐ", "ㅚ": "ㅗㅣ", "ㅝ": "ㅜㅓ", "ㅞ": "ㅜㅔ", "ㅟ": "ㅜㅣ", "ㅢ": "ㅡㅣ",
        "ㄳ": "ㄱㅅ", "ㄵ": "ㄴㅈ", "ㄶ": "ㄴㅎ", "ㄺ": "ㄹㄱ", "ㄻ": "ㄹㅁ", "ㄼ": "ㄹㅂ", "ㄽ": "ㄹㅅ",
        "ㄾ": "ㄹㅌ", "ㄿ": "ㄹㅍ", "ㅀ": "ㄹㅎ", "ㅄ": "ㅂㅅ",
    ]

    private static let syllableBase: UInt32 = 0xAC00
    private static let syllableCount: UInt32 = 11_172

    /// (initial, medial, final) indices of a precomposed syllable, or nil for anything else.
    private static func parts(of character: Character) -> (Int, Int, Int)? {
        let scalars = character.unicodeScalars
        guard scalars.count == 1, let value = scalars.first?.value,
              value >= syllableBase, value < syllableBase + syllableCount else { return nil }
        let index = Int(value - syllableBase)
        return (index / 588, (index % 588) / 28, index % 28)
    }

    /// The typed-letter sequence: syllables become their letters, Latin is lowercased,
    /// everything else passes through.
    public static func jamo(_ text: String) -> String {
        var out = ""
        for character in text.precomposedStringWithCanonicalMapping {
            if let (initial, medial, final) = parts(of: character) {
                out += initials[initial] + medials[medial] + finals[final]
            } else if let split = standaloneCompounds[character] {
                out += split
            } else {
                out += character.lowercased()
            }
        }
        return out
    }

    /// First consonant of every syllable ("클립보드" → "ㅋㄹㅂㄷ"); other characters pass through lowercased.
    public static func choseong(_ text: String) -> String {
        var out = ""
        for character in text.precomposedStringWithCanonicalMapping {
            if let (initial, _, _) = parts(of: character) {
                out += initials[initial]
            } else {
                out += character.lowercased()
            }
        }
        return out
    }

    /// True for a lone consonant letter such as ㅋ, the kind a choseong query is made of.
    static func isConsonantJamo(_ character: Character) -> Bool {
        guard let value = character.unicodeScalars.first?.value, character.unicodeScalars.count == 1 else { return false }
        return value >= 0x3131 && value <= 0x314E
    }

    static func isSyllable(_ character: Character) -> Bool { parts(of: character) != nil }
}
