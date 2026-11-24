import XCTest
@testable import ToolsmithKit

final class AnnotationTests: XCTestCase {
    private func make(_ tool: AnnotationTool, _ x1: CGFloat, _ y1: CGFloat, _ x2: CGFloat, _ y2: CGFloat, text: String = "") -> Annotation {
        Annotation(tool: tool, start: CGPoint(x: x1, y: y1), end: CGPoint(x: x2, y: y2), color: .red, lineWidth: 4, text: text, fontSize: 20)
    }

    func testRectIsNormalized() {
        XCTAssertEqual(make(.rectangle, 100, 80, 20, 10).rect, CGRect(x: 20, y: 10, width: 80, height: 70))
    }

    func testTooSmallADragIsNotAnAnnotation() {
        XCTAssertFalse(make(.rectangle, 10, 10, 11, 12).isMeaningful)
        XCTAssertTrue(make(.rectangle, 10, 10, 30, 12).isMeaningful)        // a thin box is still a box
        XCTAssertTrue(make(.arrow, 10, 10, 10, 40).isMeaningful)
        XCTAssertFalse(make(.text, 10, 10, 10, 10, text: "  ").isMeaningful)
        XCTAssertTrue(make(.text, 10, 10, 10, 10, text: "메모").isMeaningful)
    }

    func testAddUndoRedo() {
        var doc = AnnotationDocument()
        let a = make(.rectangle, 0, 0, 50, 50), b = make(.arrow, 0, 0, 80, 80)
        doc.add(a); doc.add(b)
        XCTAssertEqual(doc.items.map(\.id), [a.id, b.id]); XCTAssertTrue(doc.canUndo); XCTAssertFalse(doc.canRedo)
        doc.undo()
        XCTAssertEqual(doc.items.map(\.id), [a.id]); XCTAssertTrue(doc.canRedo)
        doc.redo()
        XCTAssertEqual(doc.items.map(\.id), [a.id, b.id])
        doc.undo(); doc.add(make(.rectangle, 5, 5, 9, 9))
        XCTAssertFalse(doc.canRedo)                                         // a new edit ends the redo trail
        doc.undo(); doc.undo(); doc.undo()                                  // more undos than edits is harmless
        XCTAssertTrue(doc.items.isEmpty); XCTAssertFalse(doc.canUndo)
    }

    func testMoveAndRemoveAreUndoable() {
        var doc = AnnotationDocument()
        let a = make(.rectangle, 10, 10, 50, 50), b = make(.rectangle, 100, 100, 150, 150)
        doc.add(a); doc.add(b)
        doc.move(a.id, by: CGSize(width: 5, height: -3))
        XCTAssertEqual(doc.items[0].rect, CGRect(x: 15, y: 7, width: 40, height: 40))
        doc.undo()
        XCTAssertEqual(doc.items[0].rect, a.rect)
        doc.remove(a.id)
        XCTAssertEqual(doc.items.map(\.id), [b.id])
        doc.undo()
        XCTAssertEqual(doc.items.map(\.id), [a.id, b.id])                   // back in its place, under b
        doc.remove(UUID()); doc.move(UUID(), by: CGSize(width: 1, height: 1))
        XCTAssertEqual(doc.items.count, 2)
    }

    func testHitTestPicksTheTopmost() {
        var doc = AnnotationDocument()
        let under = make(.rectangle, 0, 0, 100, 100), over = make(.highlight, 40, 40, 80, 80)
        doc.add(under); doc.add(over)
        XCTAssertEqual(doc.hitTest(CGPoint(x: 50, y: 50)), over.id)
        XCTAssertEqual(doc.hitTest(CGPoint(x: 10, y: 10)), under.id)
        XCTAssertNil(doc.hitTest(CGPoint(x: 300, y: 300)))
    }

    func testArrowIsHitNearItsLineOnly() {
        var doc = AnnotationDocument()
        let arrow = make(.arrow, 0, 0, 100, 100)
        doc.add(arrow)
        XCTAssertEqual(doc.hitTest(CGPoint(x: 50, y: 53)), arrow.id)
        XCTAssertNil(doc.hitTest(CGPoint(x: 90, y: 10)))                    // inside its bounding box, far from the line
    }

    func testArrowHead() {
        let head = ArrowGeometry.head(from: CGPoint(x: 0, y: 0), to: CGPoint(x: 100, y: 0), lineWidth: 4)
        XCTAssertEqual(head.tip, CGPoint(x: 100, y: 0))
        XCTAssertEqual(head.left.x, 84, accuracy: 0.001); XCTAssertEqual(head.left.y, -8, accuracy: 0.001)
        XCTAssertEqual(head.right.x, 84, accuracy: 0.001); XCTAssertEqual(head.right.y, 8, accuracy: 0.001)
        // A thin line still gets a head you can see.
        XCTAssertEqual(ArrowGeometry.headLength(lineWidth: 1), 12)
        let point = CGPoint(x: 5, y: 5)
        XCTAssertEqual(ArrowGeometry.head(from: point, to: point, lineWidth: 4).left, point)
    }

    private func stroke(_ tool: AnnotationTool, _ points: [(CGFloat, CGFloat)]) -> Annotation {
        let path = points.map { CGPoint(x: $0.0, y: $0.1) }
        return Annotation(tool: tool, start: path.first ?? .zero, end: path.last ?? .zero, color: .red, lineWidth: 4, text: "", fontSize: 20, points: path)
    }

    func testFreehandStrokeFollowsItsPoints() {
        let pen = stroke(.pen, [(10, 10), (50, 80), (120, 20)])
        XCTAssertEqual(pen.rect, CGRect(x: 10, y: 10, width: 110, height: 70))      // the box around the whole stroke
        XCTAssertTrue(pen.contains(CGPoint(x: 30, y: 46)))                           // on the first leg
        XCTAssertTrue(pen.contains(CGPoint(x: 85, y: 50)))                           // on the second leg
        XCTAssertFalse(pen.contains(CGPoint(x: 60, y: 14)))                          // inside the box, away from the line
        XCTAssertTrue(pen.isMeaningful)
        XCTAssertFalse(stroke(.pen, [(10, 10), (11, 11)]).isMeaningful)              // a dot from a click
    }

    func testMovingAStrokeMovesEveryPoint() {
        var doc = AnnotationDocument()
        let pen = stroke(.highlight, [(10, 10), (50, 80)])
        doc.add(pen)
        doc.move(pen.id, by: CGSize(width: 5, height: 5))
        XCTAssertEqual(doc.items[0].points, [CGPoint(x: 15, y: 15), CGPoint(x: 55, y: 85)])
        XCTAssertEqual(doc.items[0].start, CGPoint(x: 15, y: 15)); XCTAssertEqual(doc.items[0].end, CGPoint(x: 55, y: 85))
    }

    func testPenAndHighlighterAreFreehand() {
        XCTAssertTrue(AnnotationTool.pen.isFreehand); XCTAssertTrue(AnnotationTool.highlight.isFreehand)
        XCTAssertFalse(AnnotationTool.rectangle.isFreehand); XCTAssertFalse(AnnotationTool.arrow.isFreehand)
        XCTAssertEqual(AnnotationTool.pen.key, "p")
    }

    func testToolsHaveDistinctKeys() {
        XCTAssertEqual(Set(AnnotationTool.allCases.map(\.key)).count, AnnotationTool.allCases.count)
        XCTAssertEqual(AnnotationTool.arrow.key, "a")
        XCTAssertEqual(AnnotationTool(key: "M"), .mosaic)
        XCTAssertNil(AnnotationTool(key: "z"))
    }
}
