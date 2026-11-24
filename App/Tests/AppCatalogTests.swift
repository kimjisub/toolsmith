import XCTest
@testable import ToolsmithKit

final class AppCatalogTests: XCTestCase {
    var root: URL!
    var dirA: URL { root.appendingPathComponent("A") }
    var dirB: URL { root.appendingPathComponent("B") }

    override func setUpWithError() throws {
        root = tempFile("apps")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    /// A fake bundle: a folder named *.app with an Info.plist.
    private func makeApp(_ path: String, bundleName: String? = nil) throws {
        let app = root.appendingPathComponent(path)
        let contents = app.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        var info: [String: Any] = ["CFBundleIdentifier": "test.\(app.lastPathComponent)"]
        if let bundleName { info["CFBundleName"] = bundleName }
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            .write(to: contents.appendingPathComponent("Info.plist"))
    }

    private let fileName: (URL) -> String = { $0.deletingPathExtension().lastPathComponent }

    func testFindsAppsOneLevelDeepAndSkipsNonApps() throws {
        try makeApp("A/Slack.app"); try makeApp("A/Utilities/Terminal.app")
        try makeApp("A/Slack.app/Contents/Helper.app"); try makeApp("A/Deep/Deeper/Hidden.app")
        try Data().write(to: dirA.appendingPathComponent("readme.txt"))
        XCTAssertEqual(AppCatalog.scan([dirA], localizedName: fileName).map(\.name), ["Slack", "Terminal"])
    }

    func testLocalizedAndAlternateNames() throws {
        try makeApp("A/Notes.app", bundleName: "Notes")
        let e = AppCatalog.scan([dirA], localizedName: { _ in "메모" })[0]
        XCTAssertEqual(e.name, "메모"); XCTAssertEqual(e.alternateNames, ["Notes"])
    }

    func testLocalizedNameDropsAppExtension() throws {
        try makeApp("A/Slack.app")
        XCTAssertEqual(AppCatalog.scan([dirA], localizedName: { _ in "Slack.app" })[0].name, "Slack")
    }

    func testDuplicateNamesKeepBoth() throws {
        try makeApp("A/Slack.app"); try makeApp("B/Slack.app")
        let found = AppCatalog.scan([dirA, dirB], localizedName: { _ in "Slack" })
        XCTAssertEqual(found.count, 2); XCTAssertEqual(Set(found.map(\.url.path)).count, 2)
    }

    func testSameDirectoryTwiceIsNotDuplicated() throws {
        try makeApp("A/Slack.app")
        XCTAssertEqual(AppCatalog.scan([dirA, dirA], localizedName: fileName).count, 1)
    }

    func testDefaultDirectoriesIncludeWhereSafariReallyLives() {
        // /Applications/Safari.app is a hidden symlink that a directory listing skips; the app is in the cryptex.
        XCTAssertTrue(AppCatalog.defaultDirectories.map(\.path).contains("/System/Cryptexes/App/System/Applications"))
    }

    func testMissingDirectoryIsIgnored() {
        XCTAssertEqual(AppCatalog.scan([URL(fileURLWithPath: "/no/such/dir")], localizedName: { _ in "" }), [])
    }

    func testSortedByNameIgnoringCase() throws {
        try makeApp("A/zoom.app"); try makeApp("A/Arc.app"); try makeApp("A/Safari.app")
        XCTAssertEqual(AppCatalog.scan([dirA], localizedName: fileName).map(\.name), ["Arc", "Safari", "zoom"])
    }
}
