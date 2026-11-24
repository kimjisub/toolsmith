import XCTest
@testable import ToolsmithKit

final class HangulTextTests: XCTestCase {
    func testJamoSplitsCompoundVowelsAndFinals() {
        XCTAssertEqual(HangulText.jamo("왼쪽"), "ㅇㅗㅣㄴㅉㅗㄱ")
        XCTAssertEqual(HangulText.jamo("넓"), "ㄴㅓㄹㅂ")
        XCTAssertEqual(HangulText.jamo("Slack 앱"), "slack ㅇㅐㅂ")
    }

    func testJamoSplitsStandaloneCompoundJamo() {
        XCTAssertEqual(HangulText.jamo("ㅘㄳ"), "ㅗㅏㄱㅅ")
    }

    func testJamoNormalizesDecomposedInput() {
        // macOS file names arrive decomposed (NFD).
        XCTAssertEqual(HangulText.jamo("메모".decomposedStringWithCanonicalMapping), "ㅁㅔㅁㅗ")
    }

    func testChoseong() {
        XCTAssertEqual(HangulText.choseong("클립보드"), "ㅋㄹㅂㄷ")
        XCTAssertEqual(HangulText.choseong("왼쪽 절반"), "ㅇㅉ ㅈㅂ")
    }
}
