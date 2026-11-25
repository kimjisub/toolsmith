import Darwin
import Foundation

/// Every running process's executable path and command line, read as root (other users' processes
/// included). Used only to notice other charge-control apps.
enum RunningProcesses {
    static func descriptions() -> [String] {
        let count = proc_listallpids(nil, 0)
        guard count > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(count) + 32)
        let filled = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size))
        guard filled > 0 else { return [] }
        return pids.prefix(Int(filled)).filter { $0 > 0 }.compactMap { pid in
            let path = executablePath(pid)
            let arguments = commandLine(pid)
            let text = [path, arguments].compactMap { $0 }.joined(separator: " ")
            return text.isEmpty ? nil : text
        }
    }

    private static func executablePath(_ pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
        guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return nil }
        return String(cString: buffer)
    }

    /// The arguments after the executable path (KERN_PROCARGS2): a script run by a shell is found
    /// by its own path there.
    private static func commandLine(_ pid: pid_t) -> String? {
        var size = 0
        var name: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        guard sysctl(&name, 3, nil, &size, nil, 0) == 0, size > MemoryLayout<Int32>.size else { return nil }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctl(&name, 3, &buffer, &size, nil, 0) == 0 else { return nil }
        let argc = buffer.withUnsafeBytes { $0.load(as: Int32.self) }
        let parts = buffer[MemoryLayout<Int32>.size..<size].split(separator: 0, omittingEmptySubsequences: true)
        // The first part is the executable path, then argc arguments.
        let arguments = parts.dropFirst().prefix(Int(argc)).compactMap { String(bytes: $0, encoding: .utf8) }
        return arguments.isEmpty ? nil : arguments.joined(separator: " ")
    }
}
