import XCTest
@testable import ToolsmithKit

final class SmokeTests: XCTestCase {
    /// The identity reaches the code from project.yml through the framework's Info.plist.
    func testIdentityComesFromTheBuildSettings() {
        XCTAssertFalse(AppIdentity.name.isEmpty)
        XCTAssertFalse(AppIdentity.bundleID.contains("$("))
        XCTAssertEqual(AppIdentity.helperBundleID, AppIdentity.bundleID + ".helper")
        XCTAssertEqual(ChargeHelperIdentity.plistName, AppIdentity.bundleID + ".helper.plist")
    }
}
