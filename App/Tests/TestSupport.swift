import Foundation
import XCTest
@testable import ToolsmithKit

func tempFile(_ name: String = "file.json") -> URL {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("app-tests-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir.appendingPathComponent(name)
}

struct StubSource: CommandSource {
    let list: [Command]
    func commands() -> [Command] { list }
}

/// Collects the ids of the commands that ran.
final class RunLog {
    var ids: [String] = []
}

enum Fixture {
    static let now = Date(timeIntervalSince1970: 1_800_000_000)
    static let window = CommandSection(id: "window", title: "화면 나누기", order: 0)
    static let apps = CommandSection(id: "apps", title: "앱", order: 10)

    static func command(_ id: String, _ title: String, _ section: CommandSection, keywords: [String] = [], log: RunLog) -> Command {
        Command(id: id, title: title, subtitle: nil, keywords: keywords, section: section,
                icon: .symbol("circle"), hotkeyID: nil, run: { log.ids.append(id) })
    }

    static func commands(log: RunLog) -> [Command] {
        [
            command("window.left-half", "왼쪽 절반", window, log: log),
            command("window.left-third", "왼쪽 3분의 1", window, log: log),
            command("app:slack", "Slack", apps, keywords: ["슬랙"], log: log),
            command("app:safari", "Safari", apps, log: log),
        ]
    }
}
