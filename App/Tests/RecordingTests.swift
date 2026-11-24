import XCTest
@testable import ToolsmithKit

final class RecordingGeometryTests: XCTestCase {
    func testSourceRectIsLocalToTheDisplayWithTopLeftOrigin() {
        let primary = CGRect(x: 0, y: 0, width: 1512, height: 982)
        XCTAssertEqual(RecordingGeometry.sourceRect(selection: CGRect(x: 100, y: 200, width: 300, height: 150), displayFrame: primary),
                       CGRect(x: 100, y: 632, width: 300, height: 150))
        // A second display to the right and higher up.
        let second = CGRect(x: 1512, y: 300, width: 1440, height: 900)
        XCTAssertEqual(RecordingGeometry.sourceRect(selection: CGRect(x: 1612, y: 400, width: 200, height: 100), displayFrame: second),
                       CGRect(x: 100, y: 700, width: 200, height: 100))
    }

    func testSelectionIsClippedToTheDisplay() {
        let display = CGRect(x: 0, y: 0, width: 1000, height: 800)
        XCTAssertEqual(RecordingGeometry.sourceRect(selection: CGRect(x: 900, y: 700, width: 300, height: 300), displayFrame: display),
                       CGRect(x: 900, y: 0, width: 100, height: 100))
    }

    func testPixelSizeIsEven() {
        // Video encoders need even dimensions.
        let size = RecordingGeometry.pixelSize(points: CGSize(width: 301.5, height: 150.2), scale: 2)
        XCTAssertEqual(size.width, 602); XCTAssertEqual(size.height, 300)
        let tiny = RecordingGeometry.pixelSize(points: CGSize(width: 0.2, height: 0.2), scale: 2)
        XCTAssertEqual(tiny.width, 2); XCTAssertEqual(tiny.height, 2)
    }

    func testElapsedLabel() {
        XCTAssertEqual(RecordingGeometry.elapsedLabel(0), "00:00")
        XCTAssertEqual(RecordingGeometry.elapsedLabel(12.9), "00:12")
        XCTAssertEqual(RecordingGeometry.elapsedLabel(75), "01:15")
        XCTAssertEqual(RecordingGeometry.elapsedLabel(3_723), "1:02:03")
    }

    func testGIFFrames() {
        XCTAssertEqual(GIFPlan.frameTimes(duration: 1.0, fps: 4), [0, 0.25, 0.5, 0.75])
        XCTAssertEqual(GIFPlan.frameTimes(duration: 0.1, fps: 4), [0])
        XCTAssertEqual(GIFPlan.frameTimes(duration: 0, fps: 4), [0])
    }

    func testGIFSizeIsCappedKeepingProportion() {
        let large = GIFPlan.size(width: 1920, height: 1080, maxWidth: 960)
        XCTAssertEqual(large.width, 960); XCTAssertEqual(large.height, 540)
        let small = GIFPlan.size(width: 640, height: 480, maxWidth: 960)
        XCTAssertEqual(small.width, 640); XCTAssertEqual(small.height, 480)
    }
}
