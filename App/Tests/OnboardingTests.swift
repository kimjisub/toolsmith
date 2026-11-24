import XCTest
@testable import ToolsmithKit

final class OnboardingTests: XCTestCase {
    func testStepsInOrder() {
        XCTAssertEqual(OnboardingStep.allCases, [.welcome, .permissions, .tour, .ai, .privacy, .done])
        XCTAssertEqual(OnboardingStep.welcome.next, .permissions)
        XCTAssertEqual(OnboardingStep.done.next, .done)                 // the last step stays
        XCTAssertEqual(OnboardingStep.welcome.previous, .welcome)
        XCTAssertEqual(OnboardingStep.ai.previous, .tour)
        XCTAssertTrue(OnboardingStep.done.isLast); XCTAssertFalse(OnboardingStep.ai.isLast)
    }

    func testShownOnlyUntilCompleted() throws {
        let url = tempFile(); try Data(#"{"schemaVersion":1}"#.utf8).write(to: url)
        let store = SettingsStore(fileURL: url)
        XCTAssertFalse(store.settings.onboardingCompleted)
        store.update { $0.onboardingCompleted = true }
        XCTAssertTrue(SettingsStore(fileURL: url).settings.onboardingCompleted)
    }

    func testOpensAtLaunchOnTheSavedPageUntilCompleted() {
        let plain = ["/Applications/Toolsmith.app/Contents/MacOS/Toolsmith"]
        XCTAssertEqual(OnboardingResume.stepAtLaunch(completed: false, savedStep: nil, arguments: plain), .welcome)
        // Reopened by macOS after a permission, or by an update: the page it was on.
        XCTAssertEqual(OnboardingResume.stepAtLaunch(completed: false, savedStep: .permissions, arguments: plain), .permissions)
        XCTAssertEqual(OnboardingResume.stepAtLaunch(completed: false, savedStep: .done, arguments: plain), .done)
        XCTAssertNil(OnboardingResume.stepAtLaunch(completed: true, savedStep: .permissions, arguments: plain))
        // A development flag keeps it closed; a system option such as the language does not.
        XCTAssertNil(OnboardingResume.stepAtLaunch(completed: false, savedStep: nil, arguments: plain + ["--show-panel", "monitor"]))
        XCTAssertEqual(OnboardingResume.stepAtLaunch(completed: false, savedStep: nil, arguments: plain + ["-AppleLanguages", "(ko)"]), .welcome)
    }

    func testSavedPageSurvivesAndOlderFilesLoad() throws {
        let url = tempFile(); try Data(#"{"schemaVersion":2,"onboardingCompleted":false}"#.utf8).write(to: url)
        let store = SettingsStore(fileURL: url)
        XCTAssertNil(store.settings.onboardingStep)                     // a file from before the page was saved
        store.update { $0.onboardingStep = .permissions }
        XCTAssertEqual(SettingsStore(fileURL: url).settings.onboardingStep, .permissions)
        // A page this version does not know (written by a newer one) is dropped, not the whole file.
        try Data(#"{"schemaVersion":2,"onboardingStep":42,"windowGap":8}"#.utf8).write(to: url)
        let newer = SettingsStore(fileURL: url).settings
        XCTAssertNil(newer.onboardingStep)
        XCTAssertEqual(newer.windowGap, 8)
    }

    func testTourListsTheFeaturesWithTheirKeys() {
        let tour = OnboardingTour.items(hotkeys: .defaults.seeded(), locale: english)
        XCTAssertEqual(tour.map(\.title), ["Window Snapping", "Clipboard History", "Screen Capture", "AI Answers", "System Monitor", "Screen Time"])
        XCTAssertEqual(tour[0].keys, "⌃⌥←")                              // the key actually set, not a fixed string
        XCTAssertEqual(tour[1].keys, "⌥V")
        XCTAssertEqual(tour[2].keys, "⌥⇧4")
        XCTAssertEqual(tour[3].keys, ".")
        // A shortcut the user removed is not advertised.
        var table = HotkeyTable.defaults.seeded()
        try? table.clear("clipboard.open")
        XCTAssertNil(OnboardingTour.items(hotkeys: table)[1].keys)
    }
}

private extension HotkeyTable {
    /// The table as it is after first launch: every feature's default shortcut in place.
    func seeded() -> HotkeyTable {
        var table = self
        _ = table.seed(OnboardingTour.defaultHotkeys, alreadySeeded: [])
        return table
    }
}
