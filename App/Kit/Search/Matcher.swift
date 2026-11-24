import Foundation

/// How a query matched a candidate. Smaller is better.
public enum MatchKind: Int, Comparable, Sendable {
    /// The candidate starts with the query.
    case prefix = 0
    /// A later word of the candidate starts with the query.
    case wordPrefix
    /// The query appears somewhere inside.
    case substring
    /// The query is the first letters of the words ("ㅋㄹ" for 클립보드, "vsc" for Visual Studio Code).
    case initials

    public static func < (lhs: MatchKind, rhs: MatchKind) -> Bool { lhs.rawValue < rhs.rawValue }
}

public struct MatchScore: Comparable, Equatable, Sendable {
    public let kind: MatchKind
    /// Word index for `.wordPrefix` and `.initials`, letter offset for `.substring`, 0 for `.prefix`.
    public let position: Int

    public init(kind: MatchKind, position: Int) {
        self.kind = kind
        self.position = position
    }

    public static func < (lhs: MatchScore, rhs: MatchScore) -> Bool {
        (lhs.kind, lhs.position) < (rhs.kind, rhs.position)
    }
}

public enum Matcher {
    /// Scores `candidate` against what the user has typed so far, or nil when it does not match.
    /// Hangul is compared letter by letter, so the syllable still being composed counts.
    public static func score(query: String, candidate: String) -> MatchScore? {
        let needle = HangulText.jamo(query.trimmingCharacters(in: .whitespaces))
        guard !needle.isEmpty else { return nil }

        let words = candidate.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        // Letters of the candidate from each word to the end, so a query may span words.
        var tails: [String] = []
        for index in words.indices {
            tails.append(HangulText.jamo(words[index...].joined(separator: " ")))
        }
        guard let whole = tails.first else { return nil }

        if whole.hasPrefix(needle) { return MatchScore(kind: .prefix, position: 0) }
        for index in tails.indices.dropFirst() where tails[index].hasPrefix(needle) {
            return MatchScore(kind: .wordPrefix, position: index)
        }
        if let range = whole.range(of: needle) {
            return MatchScore(kind: .substring, position: whole.distance(from: whole.startIndex, to: range.lowerBound))
        }
        if let index = initialsMatch(needle: needle, words: words) {
            return MatchScore(kind: .initials, position: index)
        }
        return nil
    }

    /// Index of the word where the initials of the remaining words start with `needle`.
    private static func initialsMatch(needle: String, words: [String]) -> Int? {
        let allConsonants = needle.allSatisfy(HangulText.isConsonantJamo)
        let allLatin = needle.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber) }
        guard allConsonants || allLatin else { return nil }

        let perWord = words.map { word -> String in
            let composed = word.precomposedStringWithCanonicalMapping
            if composed.contains(where: HangulText.isSyllable) {
                // Every syllable contributes its first consonant.
                return String(HangulText.choseong(composed).filter(HangulText.isConsonantJamo))
            }
            // A Latin word contributes its first letter.
            return composed.first.map { $0.lowercased() } ?? ""
        }
        for index in perWord.indices where perWord[index...].joined().hasPrefix(needle) {
            return index
        }
        return nil
    }
}
