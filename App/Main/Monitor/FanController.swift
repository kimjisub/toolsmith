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
                        self.message = reply == "ok overheated" ? "온도가 \(Int(FanLimits.emergencyTemperature))° 를 넘어 자동으로 되돌렸습니다." : "팬 도우미와 연결이 끊겼습니다. 팬이 고정된 채일 수 있으니, 「직접」 을 다시 켰다가 「자동」 으로 돌리거나 맥을 재시동하세요."
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
        case "error too hot": return "지금은 온도가 높아 팬을 직접 조절할 수 없습니다."
        case "error no temperature sensor": return "이 맥의 온도를 읽을 수 없어 팬을 직접 조절하지 않습니다."
        case "error this Mac refused manual fan mode", "error this Mac refused the fan speed": return "이 맥이 팬 직접 조절을 받아들이지 않았습니다."
        case "error fan range unknown", "error no such fan": return "팬의 회전수 범위를 읽지 못했습니다."
        case "": return "팬 도우미와 연결하지 못했습니다."
        default: return "팬을 조절하지 못했습니다 (\(reply))."
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
        return "이 빌드에는 팬 조절이 들어 있지 않습니다."
        #else
        guard let executable = Bundle.main.executablePath else { return "앱의 실행 파일을 찾지 못했습니다." }
        let escaped = executable.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let script = """
            do shell script (quoted form of "\(escaped)") & " --fan-helper \(getuid()) \(ProcessInfo.processInfo.processIdentifier) >/dev/null 2>&1 &" \
            with prompt "\(AppIdentity.name) 이 팬 속도를 조절하려고 합니다." with administrator privileges
            """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return "관리자 권한을 요청하지 못했습니다." }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return "관리자 권한을 받지 못해 팬을 조절하지 않았습니다." }
        // The helper reads this Mac's sensors before it starts listening.
        for _ in 0..<40 {
            if helperIsUp() { return nil }
            usleep(250_000)
        }
        return "팬 도우미가 시작되지 않았습니다."
        #endif
    }
}
