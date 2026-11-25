import Darwin
import Foundation
import ToolsmithKit

// `toolsmith`: the command line tool inside the app (Contents/Helpers/toolsmith). It sends its
// arguments to the running app over the socket in the app's support folder and prints the answer;
// the app does the work, so a command acts exactly as the same click in the app would. When the
// app is not running it is started first.

let arguments = Array(CommandLine.arguments.dropFirst())

func connect() -> Int32? {
    let path = CLIEndpoint.socketURL.path
    var address = sockaddr_un()
    address.sun_family = sa_family_t(AF_UNIX)
    let bytes = Array(path.utf8)
    guard bytes.count < MemoryLayout.size(ofValue: address.sun_path) else { return nil }
    withUnsafeMutableBytes(of: &address.sun_path) { buffer in
        for (index, byte) in bytes.enumerated() { buffer[index] = byte }
    }
    let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
    guard descriptor >= 0 else { return nil }
    let connected = withUnsafePointer(to: &address) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
    }
    if connected != 0 { close(descriptor); return nil }
    var on: Int32 = 1
    setsockopt(descriptor, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
    return descriptor
}

/// Starts the app and waits for its socket.
func launchAndConnect() -> Int32? {
    FileHandle.standardError.write(Data("Starting \(AppIdentity.name)…\n".utf8))
    let open = Process()
    open.executableURL = URL(fileURLWithPath: "/usr/bin/open")
    open.arguments = ["-g", "-b", AppIdentity.bundleID]
    guard (try? open.run()) != nil else { return nil }
    open.waitUntilExit()
    for _ in 0..<40 {
        if let descriptor = connect() { return descriptor }
        usleep(500_000)
    }
    return nil
}

guard let descriptor = connect() ?? launchAndConnect() else {
    FileHandle.standardError.write(Data("Couldn’t reach \(AppIdentity.name). Is it installed and allowed to run?\n".utf8))
    exit(1)
}

guard let request = try? JSONEncoder().encode(CLIRequest(arguments: arguments)) else { exit(1) }
request.withUnsafeBytes { buffer in
    var offset = 0
    while offset < buffer.count {
        let written = write(descriptor, buffer.baseAddress! + offset, buffer.count - offset)
        if written <= 0 { break }
        offset += written
    }
}
shutdown(descriptor, SHUT_WR)

var reply = Data()
var chunk = [UInt8](repeating: 0, count: 65_536)
while true {
    let count = read(descriptor, &chunk, chunk.count)
    if count <= 0 { break }
    reply.append(chunk, count: count)
}
close(descriptor)

guard let response = try? JSONDecoder().decode(CLIResponse.self, from: reply) else {
    FileHandle.standardError.write(Data("\(AppIdentity.name) gave no answer.\n".utf8))
    exit(1)
}
let text = Data((response.output.hasSuffix("\n") ? response.output : response.output + "\n").utf8)
(response.exitCode == 0 ? FileHandle.standardOutput : FileHandle.standardError).write(text)
exit(response.exitCode)
