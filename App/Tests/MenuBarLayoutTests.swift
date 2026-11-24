import Foundation
import XCTest
@testable import ToolsmithKit

final class MenuBarLayoutTests: XCTestCase {
    private let a = MenuBarFixture.item("a.one", [.icon, .iconAndValue], visible: true)
    private let b = MenuBarFixture.item("b.one", [.graph, .value], visible: false)
    private let c = MenuBarFixture.item("c.one", [.icon], visible: true)
    private var available: [MenuBarItemDescriptor] { [a, b, c] }

    func testEmptyLayoutFollowsDeclarations() {
        let items = MenuBarLayout().items(available)
        XCTAssertEqual(items.map(\.id), ["a.one", "b.one", "c.one"])
        XCTAssertEqual(items.map(\.visible), [true, false, true])
        XCTAssertEqual(items.map(\.style), [.icon, .graph, .icon])
    }

    func testNewItemComesAfterTheSavedOnes() {
        let layout = MenuBarLayout(entries: [.init(id: "c.one", visible: false, style: nil), .init(id: "a.one", visible: true, style: .iconAndValue)])
        XCTAssertEqual(layout.items(available).map(\.id), ["c.one", "a.one", "b.one"])
        XCTAssertEqual(layout.items(available).map(\.style), [.icon, .iconAndValue, .graph])
    }

    func testStyleTheItemNoLongerOffersFallsBackToItsDefault() {
        let layout = MenuBarLayout(entries: [.init(id: "c.one", visible: true, style: .graph)])
        XCTAssertEqual(layout.items(available).first?.style, .icon)
    }

    func testSetStyleRefusesAStyleTheItemDoesNotHave() {
        var layout = MenuBarLayout()
        layout.setStyle("a.one", .graph, among: available)
        XCTAssertEqual(layout.items(available).first?.style, .icon)
        layout.setStyle("a.one", .iconAndValue, among: available)
        XCTAssertEqual(layout.items(available).first?.style, .iconAndValue)
    }

    func testNothingVisibleShowsTheAppIcon() {
        var layout = MenuBarLayout()
        layout.setVisible("a.one", false, among: available)
        layout.setVisible("c.one", false, among: available)
        XCTAssertEqual(layout.shown(available).map(\.id), [MenuBarItemDescriptor.appIcon.id])
        layout.setVisible("b.one", true, among: available)
        XCTAssertEqual(layout.shown(available).map(\.id), ["b.one"])
    }

    func testMoveDown() {
        var layout = MenuBarLayout()
        layout.move(fromOffsets: [0], toOffset: 3, among: available)
        XCTAssertEqual(layout.items(available).map(\.id), ["b.one", "c.one", "a.one"])
    }

    func testMoveUp() {
        var layout = MenuBarLayout()
        layout.move(fromOffsets: [2], toOffset: 0, among: available)
        XCTAssertEqual(layout.items(available).map(\.id), ["c.one", "a.one", "b.one"])
    }

    func testMoveKeepsItemsOfSwitchedOffModulesInPlace() {
        // b's module is off: the list shows a and c only, and moving them must not lose b's place.
        var layout = MenuBarLayout()
        layout.setVisible("b.one", true, among: available)
        layout.move(fromOffsets: [1], toOffset: 0, among: [a, c])
        XCTAssertEqual(layout.items([a, c]).map(\.id), ["c.one", "a.one"])
        XCTAssertEqual(layout.items(available).map(\.id), ["c.one", "b.one", "a.one"])
        XCTAssertEqual(layout.items(available)[1].visible, true)
    }

    func testOutOfRangeMoveChangesNothing() {
        var layout = MenuBarLayout()
        layout.move(fromOffsets: [7], toOffset: 0, among: available)
        XCTAssertEqual(layout.items(available).map(\.id), ["a.one", "b.one", "c.one"])
    }

    func testUnknownStyleAndDuplicatesInAFileAreTolerated() throws {
        let json = #"{"entries":[{"id":"a.one","visible":true,"style":"hologram"},{"id":"a.one","visible":false},{"id":"gone.one","visible":true}],"combined":false}"#
        let layout = try JSONDecoder().decode(MenuBarLayout.self, from: Data(json.utf8))
        XCTAssertFalse(layout.combined)
        let items = layout.items(available)
        XCTAssertEqual(items.map(\.id), ["a.one", "b.one", "c.one"])
        XCTAssertEqual(items[0].style, .icon)
        XCTAssertTrue(items[0].visible)
    }

    func testLegacyLayoutDrawsTheSameAsBefore() {
        let layout = MenuBarLayout.legacy(meters: ["memory", "battery"], readout: true)
        XCTAssertEqual(layout.shown(MenuBarFixture.all).map(\.id), ["monitor.memory", "monitor.battery", "monitor.readout"])
        XCTAssertEqual(layout.shown(MenuBarFixture.all).map(\.style), [.graph, .graph, .value])
        // Turning another meter on later puts it where it was in the old fixed order's tail.
        XCTAssertEqual(layout.items(MenuBarFixture.all).map(\.id).prefix(5), ["monitor.memory", "monitor.battery", "monitor.cpu", "monitor.disk", "monitor.network"])
    }
}
