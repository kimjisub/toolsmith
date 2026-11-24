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
