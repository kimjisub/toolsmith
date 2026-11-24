import AppKit
import Combine
import ToolsmithKit

/// The app's side of fan control: talks to the root helper, starting it (with an administrator
/// prompt) the first time the user takes manual control.
@MainActor final class FanController: ObservableObject {
    enum Mode { case auto, manual }

    @Published private(set) var mode: Mode = .auto
    /// Where the fans are held, between their slowest (0) and fastest (1).
    @Published var fraction: Double = 0.3
    @Published private(set) var isBusy = false
    /// One line about the last thing that happened (a failure, or why control was taken back).
    @Published private(set) var message: String?

    private let queue = DispatchQueue(label: "\(AppIdentity.bundleID).fan", qos: .userInitiated)
    private var watch: Timer?

    /// Holds every fan at the current fraction of its range.
    func applyManual(fans: [FanReading]) {
        guard !fans.isEmpty, !isBusy else { return }
        isBusy = true
        message = nil
        let commands = fans.map { FanCommand.set(fan: $0.index, rpm: FanLimits.rpm(fraction: fraction, minimum: $0.minimum, maximum: $0.maximum)) }
        queue.async { [weak self] in
            var failure: String?
            if !Self.helperIsUp() {
                if let error = Self.startHelper() { failure = error }
            }
            if failure == nil {
                for command in commands {
                    let reply = Self.send(command)
                    if !reply.hasPrefix("ok") { failure = Self.explain(reply); break }
                }
                // A fan that could not be set must not leave the others held.
                if failure != nil { _ = Self.send(.auto) }
            }
            DispatchQueue.main.async {
                guard let self else { return }
                self.isBusy = false
                self.message = failure
                self.mode = failure == nil ? .manual : .auto
                self.updateWatch()
            }
        }
    }

    func returnToAutomatic() {
        mode = .auto
        message = nil
        updateWatch()
        queue.async { if Self.helperIsUp() { _ = Self.send(.auto) } }
    }

    /// Called when the app quits. The helper would notice by itself within seconds; this is sooner.
    func shutdown() {
        if mode == .manual, Self.helperIsUp() { _ = Self.send(.auto) }
    }

    /// While the fans are held, ask the helper now and then whether it took them back.
    private func updateWatch() {
        watch?.invalidate()
        watch = nil
        guard mode == .manual else { return }
        let timer = Timer(timeInterval: 5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.queue.async {
                    let reply = Self.send(.ping)
                    guard reply != "ok manual" else { return }
                    DispatchQueue.main.async {
                        self.mode = .auto
                        self.message = reply == "ok overheated" ? String(localized: "The temperature passed \(Int(FanLimits.emergencyTemperature))°, so the fans went back to automatic.") : String(localized: "Lost the connection to the fan helper. The fans may be stuck at a fixed speed: turn Manual on again and back to Auto, or restart the Mac.")
                        self.updateWatch()
                    }
                }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        watch = timer
    }

    // MARK: Helper

    nonisolated private static func explain(_ reply: String) -> String {
        switch reply {
        case "error too hot": return String(localized: "It is too hot right now to control the fans manually.")
        case "error no temperature sensor": return String(localized: "This Mac’s temperature can’t be read, so the fans are not controlled manually.")
        case "error this Mac refused manual fan mode", "error this Mac refused the fan speed": return String(localized: "This Mac did not accept manual fan control.")
        case "error fan range unknown", "error no such fan": return String(localized: "Couldn’t read the fans’ speed range.")
        case "": return String(localized: "Couldn’t connect to the fan helper.")
        default: return String(localized: "Couldn’t control the fans (\(reply)).")
        }
    }

    nonisolated private static func helperIsUp() -> Bool { send(.ping).hasPrefix("ok") }

    /// Sends one command and returns the helper's one-line reply ("" when it cannot be reached).
    nonisolated private static func send(_ command: FanCommand) -> String {
        let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else { return "" }
        defer { close(descriptor) }
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let path = FanHelperProtocol.socketPath(uid: getuid())
        withUnsafeMutableBytes(of: &address.sun_path) { buffer in
            for (index, byte) in path.utf8.prefix(buffer.count - 1).enumerated() { buffer[index] = byte }
        }
        let connected = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard connected == 0 else { return "" }
        // Taking manual control can take several seconds on Apple silicon.
        var timeout = timeval(tv_sec: 10, tv_usec: 0)
        setsockopt(descriptor, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        let line = command.line + "\n"
        guard line.withCString({ write(descriptor, $0, strlen($0)) }) > 0 else { return "" }
        var buffer = [UInt8](repeating: 0, count: 128)
        let count = read(descriptor, &buffer, buffer.count)
        return count > 0 ? String(decoding: buffer.prefix(count), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines) : ""
    }

    /// Starts the helper as root. macOS asks for an administrator password. Returns why it failed, if it did.
    nonisolated private static func startHelper() -> String? {
        #if !TOOLSMITH_DEV
        return String(localized: "This build does not include fan control.")
        #else
        guard let executable = Bundle.main.executablePath else { return "Could not find the app's executable." }
        let escaped = executable.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let script = """
            do shell script (quoted form of "\(escaped)") & " --fan-helper \(getuid()) \(ProcessInfo.processInfo.processIdentifier) >/dev/null 2>&1 &" \
            with prompt "\(AppIdentity.name) wants to control the fan speed." with administrator privileges
            """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return "Could not ask for administrator rights." }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return "No administrator rights, so the fans were not changed." }
        // The helper reads this Mac's sensors before it starts listening.
        for _ in 0..<40 {
            if helperIsUp() { return nil }
            usleep(250_000)
        }
        return "The fan helper did not start."
        #endif
    }
}
