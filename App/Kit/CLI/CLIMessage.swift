import Foundation

/// The command line tool (`toolsmith`) and the running app speak over a Unix socket in the app's
/// support folder: one JSON request, one JSON response, then the connection closes. The socket is
/// readable by its owner only and the app checks the other side's user id, so only the same user
/// reaches the app. Output is English and stable, for scripts; `--json` gives the structured form.
public enum CLIEndpoint {
    public static var socketURL: URL { SettingsStore.supportDirectory.appendingPathComponent("cli.sock") }
}

public struct CLIRequest: Codable, Equatable, Sendable {
    /// Everything after the tool's name: `["charge", "limit", "80"]`.
    public var arguments: [String]

    public init(arguments: [String]) {
        self.arguments = arguments
    }

    /// `--json` anywhere asks for JSON output; the other arguments without it.
    public var wantsJSON: Bool { arguments.contains("--json") }
    public var words: [String] { arguments.filter { $0 != "--json" } }
}

public struct CLIResponse: Codable, Equatable, Sendable {
    /// 0 done; 1 refused or failed; 2 not understood (usage).
    public var exitCode: Int32
    /// What to print: text for standard output, or the error for standard error.
    public var output: String

    public init(exitCode: Int32 = 0, output: String) {
        self.exitCode = exitCode
        self.output = output
    }

    public static func usage(_ text: String) -> CLIResponse { CLIResponse(exitCode: 2, output: text) }
    public static func failure(_ text: String) -> CLIResponse { CLIResponse(exitCode: 1, output: text) }

    /// A value as pretty, key-sorted JSON.
    public static func json<Value: Encodable>(_ value: Value) -> CLIResponse {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let text = (try? encoder.encode(value)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        return CLIResponse(output: text)
    }
}
