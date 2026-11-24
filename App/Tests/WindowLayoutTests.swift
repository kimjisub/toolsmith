import XCTest
@testable import ToolsmithKit

final class WindowLayoutTests: XCTestCase {
    let v = CGRect(x: 0, y: 0, width: 1200, height: 900)
    let w = CGRect(x: 50, y: 60, width: 400, height: 300)

    private func frame(_ action: WindowAction, visible: CGRect? = nil, window: CGRect? = nil, gap: CGFloat = 0) -> CGRect? {
        WindowLayout.frame(for: action, window: window ?? w, visible: visible ?? v, gap: gap)
    }

    func testHalves() {
        XCTAssertEqual(frame(.leftHalf), CGRect(x: 0, y: 0, width: 600, height: 900))
        XCTAssertEqual(frame(.rightHalf), CGRect(x: 600, y: 0, width: 600, height: 900))
        XCTAssertEqual(frame(.topHalf), CGRect(x: 0, y: 0, width: 1200, height: 450))
        XCTAssertEqual(frame(.bottomHalf), CGRect(x: 0, y: 450, width: 1200, height: 450))
    }

    func testThirds() {
        XCTAssertEqual(frame(.leftThird), CGRect(x: 0, y: 0, width: 400, height: 900))
        XCTAssertEqual(frame(.centerThird), CGRect(x: 400, y: 0, width: 400, height: 900))
        XCTAssertEqual(frame(.rightThird), CGRect(x: 800, y: 0, width: 400, height: 900))
        XCTAssertEqual(frame(.leftTwoThirds), CGRect(x: 0, y: 0, width: 800, height: 900))
        XCTAssertEqual(frame(.rightTwoThirds), CGRect(x: 400, y: 0, width: 800, height: 900))
    }

    func testCornersAndMaximize() {
        XCTAssertEqual(frame(.topLeft), CGRect(x: 0, y: 0, width: 600, height: 450))
        XCTAssertEqual(frame(.topRight), CGRect(x: 600, y: 0, width: 600, height: 450))
        XCTAssertEqual(frame(.bottomLeft), CGRect(x: 0, y: 450, width: 600, height: 450))
        XCTAssertEqual(frame(.bottomRight), CGRect(x: 600, y: 450, width: 600, height: 450))
        XCTAssertEqual(frame(.maximize), v)
    }

    func testVisibleAreaOffset() {
        // Below a 25pt menu bar, on a display to the right of another.
        let offset = CGRect(x: 1512, y: 25, width: 1200, height: 900)
        XCTAssertEqual(frame(.rightHalf, visible: offset), CGRect(x: 2112, y: 25, width: 600, height: 900))
    }

    func testGap() {
        XCTAssertEqual(frame(.leftHalf, gap: 10), CGRect(x: 10, y: 10, width: 585, height: 880))
        XCTAssertEqual(frame(.rightHalf, gap: 10), CGRect(x: 605, y: 10, width: 585, height: 880))
        XCTAssertEqual(frame(.maximize, gap: 10), CGRect(x: 10, y: 10, width: 1180, height: 880))
        let wide = CGRect(x: 0, y: 0, width: 1240, height: 900)
        XCTAssertEqual(frame(.leftTwoThirds, visible: wide, gap: 10), CGRect(x: 10, y: 10, width: 810, height: 880))
        XCTAssertEqual(frame(.rightThird, visible: wide, gap: 10), CGRect(x: 830, y: 10, width: 400, height: 880))
        XCTAssertEqual(frame(.bottomRight, gap: 10), CGRect(x: 605, y: 455, width: 585, height: 435))
    }

    func testCenterKeepsSizeAndClampsOversizedWindows() {
        XCTAssertEqual(frame(.center), CGRect(x: 400, y: 300, width: 400, height: 300))
        XCTAssertEqual(frame(.center, window: CGRect(x: 0, y: 0, width: 2000, height: 1000)), v)
    }

    func testActionsThatNeedMoreThanOneScreenHaveNoFrame() {
        XCTAssertNil(frame(.nextDisplay)); XCTAssertNil(frame(.previousDisplay)); XCTAssertNil(frame(.restore))
    }

    func testMovedKeepsRelativePlaceAndSize() {
        let from = CGRect(x: 0, y: 0, width: 1200, height: 900)
        let to = CGRect(x: 1200, y: 0, width: 2400, height: 1800)
        XCTAssertEqual(WindowLayout.moved(CGRect(x: 100, y: 100, width: 600, height: 450), from: from, to: to),
                       CGRect(x: 1400, y: 200, width: 1200, height: 900))
    }

    func testMovedStaysInsideTheTargetScreen() {
        // A window hanging off the right edge of the source ends up fully inside the target.
        let from = CGRect(x: 0, y: 0, width: 1200, height: 900)
        let to = CGRect(x: 1200, y: 0, width: 1200, height: 900)
        let moved = WindowLayout.moved(CGRect(x: 1000, y: 800, width: 600, height: 450), from: from, to: to)
        XCTAssertTrue(to.contains(moved), "\(moved)")
        XCTAssertEqual(moved.size, CGSize(width: 600, height: 450))
    }
}

final class WindowActionTests: XCTestCase {
    func testEighteenActionsWithUniqueIDs() {
        XCTAssertEqual(WindowAction.allCases.count, 18)
        XCTAssertEqual(Set(WindowAction.allCases.map(\.id)).count, 18)
        XCTAssertEqual(WindowAction.leftHalf.id, "window.left-half")
        XCTAssertEqual(WindowAction.leftHalf.title(locale: english), "Left Half")
    }

    func testDefaultHotkeys() {
        let defaults = WindowAction.defaultHotkeys
        XCTAssertEqual(defaults.count, 6)
        XCTAssertEqual(defaults["window.left-half"]?.display, "⌃⌥←")
        XCTAssertEqual(defaults["window.right-half"]?.display, "⌃⌥→")
        XCTAssertEqual(defaults["window.top-half"]?.display, "⌃⌥↑")
        XCTAssertEqual(defaults["window.bottom-half"]?.display, "⌃⌥↓")
        XCTAssertEqual(defaults["window.maximize"]?.display, "⌃⌥↵")
        XCTAssertEqual(defaults["window.center"]?.display, "⌃⌥C")
    }

    func testFoundByKoreanAndEnglish() {
        XCTAssertNotNil(Matcher.score(query: "left h", candidate: WindowAction.leftHalf.title(locale: english)))
        XCTAssertTrue(WindowAction.leftHalf.keywords.contains { Matcher.score(query: "좌", candidate: $0) != nil })
        XCTAssertTrue(WindowAction.maximize.keywords.contains { Matcher.score(query: "max", candidate: $0) != nil })
    }
}
