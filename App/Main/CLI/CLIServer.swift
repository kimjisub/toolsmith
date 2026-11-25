import Darwin
import Foundation
import ToolsmithKit

/// The running app's end of the `toolsmith` command line tool: a Unix socket in the support folder
/// (`CLIEndpoint`), owner-only, that takes one JSON request per connection from the same user and
/// answers it. App-wide words (`help`, `status`) are answered here; `toolsmith <name> …` goes to the
/// running module whose `commandLine` has that name.
@MainActor final class CLIServer {
    private let modules: ModuleManager
    private var socket: Int32 = -1
    private var source: DispatchSourceRead?

    init(modules: ModuleManager) {
        self.modules = modules
    }

    func start() {
        guard source == nil else { return }
        let path = CLIEndpoint.socketURL.path
        try? FileManager.default.createDirectory(at: CLIEndpoint.socketURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        unlink(path)
        let listener = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard listener >= 0, var address = Self.address(path) else { return }
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(listener, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard bound == 0, chmod(path, 0o600) == 0, listen(listener, 8) == 0 else { close(listener); return }
        socket = listener
        let source = DispatchSource.makeReadSource(fileDescriptor: listener, queue: .main)
        source.setEventHandler { [weak self] in self?.accept() }
        source.setCancelHandler { close(listener); unlink(path) }
        source.resume()
        self.source = source
    }

    func stop() {
        source?.cancel()
        source = nil
        socket = -1
    }

    private func accept() {
        let connection = Darwin.accept(socket, nil, nil)
        guard connection >= 0 else { return }
        // Only the user the app runs as.
        var uid: uid_t = 0, gid: gid_t = 0
        guard getpeereid(connection, &uid, &gid) == 0, uid == getuid() else { close(connection); return }
        var on: Int32 = 1
        setsockopt(connection, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
        var timeout = timeval(tv_sec: 5, tv_usec: 0)
        setsockopt(connection, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        // Reading and writing happen off the main thread; only the answer runs on it.
        DispatchQueue.global(qos: .userInitiated).async {
            let request = Self.readAll(connection).flatMap { try? JSONDecoder().decode(CLIRequest.self, from: $0) }
            Task { @MainActor in
                let response = if let request { await self.answer(request) } else { CLIResponse.failure("Couldn’t read the request.") }
                let data = (try? JSONEncoder().encode(response)) ?? Data()
                DispatchQueue.global(qos: .userInitiated).async {
                    Self.writeAll(data, to: connection)
                    close(connection)
                }
            }
        }
    }

    private func answer(_ request: CLIRequest) async -> CLIResponse {
        let words = request.words
        guard let first = words.first, !["help", "--help", "-h"].contains(first) else { return .init(output: usage) }
        if first == "status" { return status(json: request.wantsJSON) }
        guard let module = modules.modules.first(where: { $0.commandLine?.name == first }), let commandLine = module.commandLine else {
            return .usage("Unknown command: \(first)\n\n\(usage)")
        }
        guard modules.isEnabled(module.descriptor.id) else {
            return .failure("\(module.descriptor.title) is switched off. Switch it on in \(AppIdentity.name) Settings → Features.")
        }
        let rest = CLIRequest(arguments: Array(request.arguments.drop { $0 != first }.dropFirst()))
        if rest.words.first.map({ ["help", "--help", "-h"].contains($0) }) == true { return .init(output: commandLine.usage) }
        return await commandLine.run(rest)
    }

    private var usage: String {
        let commands = modules.modules.compactMap(\.commandLine).map { "  \($0.name.padding(toLength: 12, withPad: " ", startingAt: 0)) see toolsmith \($0.name) --help" }
        return (["Usage: toolsmith <command> [--json]", "", "  status       The app's version and which features run"] + commands).joined(separator: "\n")
    }

    private struct Status: Codable {
        let version: String
        let build: String
        let running: [String]
    }

    private func status(json: Bool) -> CLIResponse {
        let info = Bundle.main.infoDictionary
        let status = Status(version: info?["CFBundleShortVersionString"] as? String ?? "?", build: info?["CFBundleVersion"] as? String ?? "?",
                            running: modules.running.map(\.descriptor.id))
        if json { return .json(status) }
        return CLIResponse(output: "\(AppIdentity.name) \(status.version) (\(status.build))\nrunning: \(status.running.joined(separator: ", "))")
    }

    private static func address(_ path: String) -> sockaddr_un? {
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8)
        guard bytes.count < MemoryLayout.size(ofValue: address.sun_path) else { return nil }
        withUnsafeMutableBytes(of: &address.sun_path) { buffer in
            for (index, byte) in bytes.enumerated() { buffer[index] = byte }
        }
        return address
    }

    /// The request is small and the client shuts its writing side when done.
    nonisolated private static func readAll(_ connection: Int32) -> Data? {
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            let count = read(connection, &buffer, buffer.count)
            if count < 0 { return nil }
            if count == 0 { return data }
            data.append(buffer, count: count)
            if data.count > 1_000_000 { return nil }
        }
    }

    nonisolated private static func writeAll(_ data: Data, to connection: Int32) {
        data.withUnsafeBytes { buffer in
            var offset = 0
            while offset < buffer.count {
                let written = write(connection, buffer.baseAddress! + offset, buffer.count - offset)
                if written <= 0 { return }
                offset += written
            }
        }
    }
}
