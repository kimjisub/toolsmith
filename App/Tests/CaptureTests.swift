import XCTest
@testable import ToolsmithKit

final class CaptureGeometryTests: XCTestCase {
    func testRectFromAnyDragDirection() {
        XCTAssertEqual(CaptureGeometry.rect(from: CGPoint(x: 100, y: 50), to: CGPoint(x: 20, y: 10)), CGRect(x: 20, y: 10, width: 80, height: 40))
        XCTAssertEqual(CaptureGeometry.rect(from: CGPoint(x: 20, y: 10), to: CGPoint(x: 100, y: 50)), CGRect(x: 20, y: 10, width: 80, height: 40))
    }

    func testRectIsWholePoints() {
        XCTAssertEqual(CaptureGeometry.rect(from: CGPoint(x: 10.4, y: 10.6), to: CGPoint(x: 20.5, y: 30.2)), CGRect(x: 10, y: 11, width: 10, height: 20))
    }

    func testFlippingToTopLeftOrigin() {
        // AppKit measures up from the bottom of the primary display; capture APIs measure down from its top.
        XCTAssertEqual(CaptureGeometry.topLeftOrigin(CGRect(x: 100, y: 200, width: 300, height: 150), primaryHeight: 982),
                       CGRect(x: 100, y: 632, width: 300, height: 150))
        // A display above the primary has negative y in the flipped space.
        XCTAssertEqual(CaptureGeometry.topLeftOrigin(CGRect(x: 0, y: 982, width: 100, height: 100), primaryHeight: 982).minY, -100)
    }

    func testSizeLabelAndUsable() {
        XCTAssertEqual(CaptureGeometry.sizeLabel(CGSize(width: 640, height: 480)), "640 × 480")
        XCTAssertEqual(CaptureGeometry.sizeLabel(CGSize(width: 640.4, height: 479.6)), "640 × 480")
        XCTAssertTrue(CaptureGeometry.isUsable(CGRect(x: 0, y: 0, width: 4, height: 4)))
        XCTAssertFalse(CaptureGeometry.isUsable(CGRect(x: 0, y: 0, width: 3, height: 200)))   // a click, not a drag
    }

    func testFileName() {
        let seoul = TimeZone(identifier: "Asia/Seoul")!
        let date = Date(timeIntervalSince1970: 1_800_000_000)       // 2027-01-15 17:00:00 KST
        XCTAssertEqual(CaptureFileName.name(date: date, ext: "png", timeZone: seoul), "\(AppIdentity.name) 2027-01-15 17.00.00.png")
        XCTAssertEqual(CaptureFileName.name(date: date, ext: "mp4", timeZone: seoul), "\(AppIdentity.name) 2027-01-15 17.00.00.mp4")
    }

    func testUniqueURLAddsACounter() throws {
        let dir = tempFile("captures"); try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let first = CaptureFileName.uniqueURL(in: dir, name: "a.png")
        XCTAssertEqual(first.lastPathComponent, "a.png")
        try Data().write(to: first)
        XCTAssertEqual(CaptureFileName.uniqueURL(in: dir, name: "a.png").lastPathComponent, "a 2.png")
        try Data().write(to: dir.appendingPathComponent("a 2.png"))
        XCTAssertEqual(CaptureFileName.uniqueURL(in: dir, name: "a.png").lastPathComponent, "a 3.png")
    }
}

final class RGBColorTests: XCTestCase {
    func testFormats() {
        let peach = RGBColor(red: 255, green: 201, blue: 163)
        XCTAssertEqual(ColorFormat.hex.text(peach), "#FFC9A3")
        XCTAssertEqual(ColorFormat.rgb.text(peach), "rgb(255, 201, 163)")
        XCTAssertEqual(ColorFormat.hsl.text(peach), "hsl(25, 100%, 82%)")
    }

    func testGraysHaveNoHueOrSaturation() {
        XCTAssertEqual(ColorFormat.hsl.text(RGBColor(red: 0, green: 0, blue: 0)), "hsl(0, 0%, 0%)")
        XCTAssertEqual(ColorFormat.hsl.text(RGBColor(red: 255, green: 255, blue: 255)), "hsl(0, 0%, 100%)")
        XCTAssertEqual(ColorFormat.hex.text(RGBColor(red: 0, green: 10, blue: 255)), "#000AFF")
    }

    func testFromUnitComponentsClamps() {
        XCTAssertEqual(RGBColor(unitRed: 1.2, green: -0.1, blue: 0.5), RGBColor(red: 255, green: 0, blue: 128))
    }
}
