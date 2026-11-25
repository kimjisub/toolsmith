import XCTest
@testable import ToolsmithKit

final class CommandLineTests: XCTestCase {
    func testRequestsSplitOffJSON() {
        let request = CLIRequest(arguments: ["charge", "status", "--json"])
        XCTAssertTrue(request.wantsJSON)
        XCTAssertEqual(request.words, ["charge", "status"])
        XCTAssertFalse(CLIRequest(arguments: ["status"]).wantsJSON)
    }

    func testResponsesRoundTrip() throws {
        let response = CLIResponse.usage("nope")
        XCTAssertEqual(response.exitCode, 2)
        XCTAssertEqual(try JSONDecoder().decode(CLIResponse.self, from: JSONEncoder().encode(response)), response)
        XCTAssertTrue(CLIResponse.json(["a": 1]).output.contains("\"a\" : 1"))
    }

    func testChargeCommandsParse() throws {
        XCTAssertEqual(try ChargeCommand.parse([]), .status)
        XCTAssertEqual(try ChargeCommand.parse(["status"]), .status)
        XCTAssertEqual(try ChargeCommand.parse(["limit", "80"]), .limit(80))
        XCTAssertEqual(try ChargeCommand.parse(["limit", "80%"]), .limit(80))
        XCTAssertEqual(try ChargeCommand.parse(["limit", "100"]), .limit(nil))
        XCTAssertEqual(try ChargeCommand.parse(["limit", "OFF"]), .limit(nil))
        XCTAssertEqual(try ChargeCommand.parse(["sailing", "10"]), .sailing(10))
        XCTAssertEqual(try ChargeCommand.parse(["discharge", "on"]), .discharge(true))
        XCTAssertEqual(try ChargeCommand.parse(["topup", "off"]), .topUp(false))
        XCTAssertEqual(try ChargeCommand.parse(["helper", "status"]), .helperStatus)
        XCTAssertEqual(try ChargeCommand.parse(["helper", "install"]), .helperInstall(wait: false))
        XCTAssertEqual(try ChargeCommand.parse(["helper", "install", "--wait"]), .helperInstall(wait: true))
        XCTAssertEqual(try ChargeCommand.parse(["helper", "uninstall"]), .helperUninstall)
    }

    func testBadChargeCommandsSayWhy() {
        for words in [["limit", "30"], ["limit"], ["limit", "80", "90"], ["sailing", "7"], ["discharge", "yes"], ["helper"], ["helper", "remove"], ["fly"], ["status", "now"]] {
            XCTAssertThrowsError(try ChargeCommand.parse(words), "\(words)") { error in
                guard case ChargeCommand.ParseError.usage(let reason) = error else { return XCTFail("\(error)") }
                XCTAssertFalse(reason.isEmpty)
            }
        }
    }

    func testTheReportReadsForPeopleAndScripts() throws {
        let report = ChargeReport(activity: "holding", summary: "Sailing at 78%", level: 78, onAdapter: true, limit: 80, sailing: 5,
                                  helper: "running", method: "nativeLimit", systemLimit: 78, conflicts: ["AlDente"])
        XCTAssertEqual(report.text, """
        state: Sailing at 78%
        battery: 78%, adapter connected
        limit: 80%
        sailing: 5 points
        helper: running
        method: nativeLimit
        macOS limit: 78%
        other charge apps: AlDente (nothing is changed while they run)
        """)
        XCTAssertEqual(try JSONDecoder().decode(ChargeReport.self, from: JSONEncoder().encode(report)), report)
        XCTAssertEqual(ChargeReport(helper: "notInstalled").text, "helper: notInstalled")
    }
}
