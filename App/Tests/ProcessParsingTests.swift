import XCTest
@testable import ToolsmithKit

final class ProcessParsingTests: XCTestCase {
    func testTopStreamGivesBlocks() {
        var parser = TopStreamParser()
        let lines = [
            "Processes: 900 total", "Load Avg: 3.1", "", "PID    %CPU MEM    POWER COMMAND",
            "416    15.6 2105M+ 15.6  WindowServer", "855    14.0 110M   14.0  io.tailscale.ipn",
            "Processes: 901 total", "PID    %CPU MEM    POWER COMMAND", "1      0.1  12K    0.0   launchd",
            "Processes: 902 total",
        ]
        let blocks = lines.compactMap { parser.feed($0) }
        XCTAssertEqual(blocks.count, 2)
        XCTAssertEqual(blocks[0].map(\.pid), [416, 855])
        XCTAssertEqual(blocks[0][0], ProcessSample(pid: 416, command: "WindowServer", cpu: 15.6, memory: 2_105 * 1_048_576, energy: 15.6))
        XCTAssertEqual(blocks[1][0].memory, 12 * 1_024)
    }

    func testTopCommandsKeepSpaces() {
        XCTAssertEqual(TopStreamParser.row("123  1.0  1G  0.5  Google Chrome He")?.command, "Google Chrome He")
        XCTAssertNil(TopStreamParser.row("garbage line"))
    }

    func testTopMemoryUnits() {
        XCTAssertEqual(TopStreamParser.memory("10M-"), 10 * 1_048_576)
        XCTAssertEqual(TopStreamParser.memory("1.5G"), UInt64(1.5 * 1_073_741_824))
        XCTAssertEqual(TopStreamParser.memory("512K"), 512 * 1_024)
        XCTAssertEqual(TopStreamParser.memory("900B"), 900)
        XCTAssertNil(TopStreamParser.memory(""))
        XCTAssertNil(TopStreamParser.memory("infM"))
        XCTAssertNil(TopStreamParser.memory("-5K"))
        XCTAssertNil(TopStreamParser.row("12  nan  1M  0  evil"))
        XCTAssertNil(TopStreamParser.row("12  inf  1M  0  evil"))
    }

    func testNettopStream() {
        var parser = NettopStreamParser()
        let lines = [",bytes_in,bytes_out,", "kernel_task.0,100,200,", "Google Chrome H.812,5000,700,", ",bytes_in,bytes_out,"]
        let blocks = lines.compactMap { parser.feed($0) }
        XCTAssertEqual(blocks.count, 1)
        XCTAssertEqual(blocks[0][812]?.name, "Google Chrome H")
        XCTAssertEqual(blocks[0][812]?.received, 5_000)
        XCTAssertEqual(blocks[0][0]?.sent, 200)
    }

    func testAppGroupingFindsOutermostApp() {
        XCTAssertEqual(AppGrouping.appBundle(forExecutable: "/Applications/Google Chrome.app/Contents/Frameworks/G.framework/Helpers/Google Chrome Helper (Renderer).app/Contents/MacOS/Google Chrome Helper (Renderer)"),
                       "/Applications/Google Chrome.app")
        XCTAssertNil(AppGrouping.appBundle(forExecutable: "/System/Library/PrivateFrameworks/SkyLight.framework/Resources/WindowServer"))
    }

    func testRankingAddsHelpersToTheirApp() {
        let identity: (Int32) -> (id: String, name: String, path: String?) = { pid in
            pid < 10 ? ("chrome", "Google Chrome", "/Applications/Google Chrome.app") : ("pid:\(pid)", "proc\(pid)", nil)
        }
        let ranked = UsageRanking.top([(1, 10), (2, 15), (11, 20), (12, 0)], limit: 5, identity: identity)
        XCTAssertEqual(ranked.map(\.name), ["Google Chrome", "proc11"])
        XCTAssertEqual(ranked[0].value, 25)
        XCTAssertEqual(UsageRanking.top([(1, 10), (11, 20)], limit: 1, identity: identity).map(\.name), ["proc11"])
    }
}
