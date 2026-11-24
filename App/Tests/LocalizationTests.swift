import XCTest
@testable import ToolsmithKit

/// The framework's text in both languages it ships, whatever the language of the Mac running the tests.
final class LocalizationTests: XCTestCase {
    private let korean = Locale(identifier: "ko_KR")

    func testTheFrameworkShipsEveryLanguage() {
        for language in AppLanguage.shipped {
            XCTAssertTrue(Bundle.kit.localizations.contains(language), "\(language) missing from ToolsmithKit")
        }
    }

    func testWordsComeFromTheCatalogInTheAskedLanguage() {
        XCTAssertEqual(WindowAction.leftHalf.title(locale: english), "Left Half")
        XCTAssertEqual(WindowAction.leftHalf.title(locale: korean), "왼쪽 절반")
        XCTAssertEqual(localized("Graph", locale: english), "Graph")
        XCTAssertEqual(localized("Graph", locale: korean), "그래프")
        XCTAssertEqual(AppLanguage.system.label(locale: korean), "시스템 설정 따르기")
    }

    func testALaunchCommandIsFoundByItsNameInEitherLanguage() {
        let log = RunLog()
        let command = Command(id: WindowAction.leftHalf.id, localizedTitle: WindowAction.leftHalf.titleResource, subtitle: nil,
                              keywords: [], section: Fixture.window, icon: .symbol("circle"), hotkeyID: nil, run: { log.ids.append("left") })
        let engine = LauncherEngine(sources: [StubSource(list: [command])], usage: UsageLog(fileURL: tempFile()), now: { Fixture.now })
        engine.reload()
        for query in ["left", "왼쪽", "왼", "ㅇㅉ"] {
            XCTAssertEqual(engine.results(for: query).first?.commandIDs, [command.id], query)
        }
    }

    func testRelativeTimesFollowTheLocale() {
        let now = Fixture.now
        XCTAssertEqual(RelativeTime.text(from: now.addingTimeInterval(-10), now: now, locale: english), "Just now")
        XCTAssertEqual(RelativeTime.text(from: now.addingTimeInterval(-10), now: now, locale: korean), "방금")
        XCTAssertEqual(RelativeTime.text(from: now.addingTimeInterval(-14 * 60), now: now, locale: english), "14 minutes ago")
        XCTAssertEqual(RelativeTime.text(from: now.addingTimeInterval(-14 * 60), now: now, locale: korean), "14분 전")
        XCTAssertEqual(RelativeTime.text(from: now.addingTimeInterval(-60), now: now, locale: english), "1 minute ago")
    }

    func testDurationsSizesAndHoursFollowTheLocale() {
        XCTAssertEqual(DurationText.text(3 * 3_600 + 12 * 60, locale: english), "3 hr, 12 min")
        XCTAssertEqual(DurationText.text(3 * 3_600 + 12 * 60, locale: korean), "3시간 12분")
        XCTAssertEqual(DurationText.text(20, locale: korean), "1분 미만")
        XCTAssertEqual(DurationText.hour(14, locale: english), "2\u{202F}PM")
        XCTAssertEqual(DurationText.hour(14, locale: korean), "오후 2시")
        XCTAssertEqual(ByteSize.text(1_500, locale: english), "1.5 KB")
        XCTAssertEqual(ByteSize.text(1_500, locale: korean), "1.5KB")
    }

    func testAppLanguageMatchesTheAppleLanguagesPreference() {
        XCTAssertEqual(AppLanguage(preferredLanguages: nil), .system)
        XCTAssertEqual(AppLanguage(preferredLanguages: []), .system)
        XCTAssertEqual(AppLanguage(preferredLanguages: ["ko-KR"]), .korean)
        XCTAssertEqual(AppLanguage(preferredLanguages: ["en"]), .english)
        XCTAssertEqual(AppLanguage(preferredLanguages: ["ja"]), .system)
        XCTAssertEqual(AppLanguage.korean.preferredLanguages, ["ko"])
        XCTAssertNil(AppLanguage.system.preferredLanguages)
        for language in AppLanguage.allCases {
            XCTAssertEqual(AppLanguage(preferredLanguages: language.preferredLanguages), language)
        }
    }
}
