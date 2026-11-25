import Foundation

/// One command of `toolsmith`: the word after the tool's name and what its `--help` prints.
public struct CLICommandHelp: Equatable, Sendable {
    public let name: String
    public let usage: String
}

/// What `toolsmith` can say without the app: the usage, a command's `--help`, and an unknown
/// command. The tool answers these itself, so asking for help never starts the app; the app's
/// `CLIServer` answers them the same way for a request that reaches it.
public enum CLIHelp {
    public static let charge = CLICommandHelp(name: "charge", usage: ChargeCommand.usage)
    /// Every module command, in the order the usage lists them. A module's `ModuleCommandLine` takes its entry here.
    public static let commands = [charge]

    static let helpWords: Set<String> = ["help", "--help", "-h"]

    public static let usage = (["Usage: toolsmith <command> [--json]", "", "  status       The app's version and which features run"]
        + commands.map { "  \($0.name.padding(toLength: 12, withPad: " ", startingAt: 0)) see toolsmith \($0.name) --help" })
        .joined(separator: "\n")

    /// The answer when the request needs no app, nil when the app has to run it.
    public static func answer(_ request: CLIRequest) -> CLIResponse? {
        let words = request.words
        guard let first = words.first, !helpWords.contains(first) else { return CLIResponse(output: usage) }
        if first == "status" { return nil }
        guard let command = commands.first(where: { $0.name == first }) else {
            return .usage("Unknown command: \(first)\n\n\(usage)")
        }
        if words.dropFirst().first.map(helpWords.contains) == true { return CLIResponse(output: command.usage) }
        return nil
    }
}
