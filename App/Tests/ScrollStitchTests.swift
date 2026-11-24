import XCTest
@testable import ToolsmithKit

final class ScrollStitchTests: XCTestCase {
    /// A page of 1000 distinct rows; a frame shows 100 of them starting at `top`.
    private func frame(top: Int, height: Int = 100) -> [UInt64] { (top..<(top + height)).map { UInt64($0) &* 2_654_435_761 } }

    func testFindsHowFarThePageMoved() {
        XCTAssertEqual(ScrollStitch.shift(previous: frame(top: 0), next: frame(top: 30)), 30)
        XCTAssertEqual(ScrollStitch.shift(previous: frame(top: 200), next: frame(top: 275)), 75)
    }

    func testNoMovementIsZero() {
        XCTAssertEqual(ScrollStitch.shift(previous: frame(top: 40), next: frame(top: 40)), 0)
    }

    func testUnrelatedFramesHaveNoShift() {
        XCTAssertNil(ScrollStitch.shift(previous: frame(top: 0), next: frame(top: 500)))
        XCTAssertNil(ScrollStitch.shift(previous: frame(top: 0), next: frame(top: 0, height: 80)))   // different sizes
        XCTAssertNil(ScrollStitch.shift(previous: [], next: []))
    }

    func testStickyHeaderIsIgnored() {
        // The top 12 rows stay the same (a header that does not scroll) while the rest moves by 40.
        let header = (0..<12).map { UInt64(9_000_000 + $0) }
        let previous = header + frame(top: 12, height: 88)
        let next = header + frame(top: 52, height: 88)
        XCTAssertEqual(ScrollStitch.shift(previous: previous, next: next), 40)
    }

    func testAFewDifferentRowsAreTolerated() {
        // A blinking caret or a hover effect changes a couple of rows.
        var next = frame(top: 30)
        next[10] = 1; next[55] = 2
        XCTAssertEqual(ScrollStitch.shift(previous: frame(top: 0), next: next), 30)
    }

    func testRepeatingContentPrefersTheSmallestShiftThatFits() {
        // Blank rows everywhere: any shift fits, so the honest answer is "did not move".
        let blank = [UInt64](repeating: 7, count: 100)
        XCTAssertEqual(ScrollStitch.shift(previous: blank, next: blank), 0)
    }

    func testPlanAppendsOnlyTheNewRows() {
        var plan = ScrollStitch.Plan(frameHeight: 100)
        XCTAssertEqual(plan.totalHeight, 100)
        XCTAssertEqual(plan.append(shift: 30), 70..<100)      // rows of the new frame that are new
        XCTAssertEqual(plan.totalHeight, 130)
        XCTAssertNil(plan.append(shift: 0))                   // nothing moved: nothing to add
        XCTAssertEqual(plan.append(shift: 100), 0..<100)      // moved a whole frame
        XCTAssertEqual(plan.totalHeight, 230)
    }
}
