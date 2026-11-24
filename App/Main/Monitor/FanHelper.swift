#if TOOLSMITH_DEV
import Darwin
import Foundation
import ToolsmithKit

/// The part of fan control that runs as root. The app starts this same executable with
/// `--fan-helper <uid> <pid>` through an administrator prompt; it stays up for as long as the app
/// does and then gives the fans back to the system.
///
/// DEVELOPMENT ONLY. Root runs this executable from wherever the app lives, and it loads the app's
/// framework: on a team Mac that would let anything able to write those files become root at the
/// next password prompt. A build for the team needs a separate, minimal, root-owned, Developer ID
/// signed helper (SMAppService daemon) that checks who is calling it.
///
/// It understands three commands (`FanCommand`) and nothing else, accepts connections only from
/// the user who started it, and never sets a speed outside the fan's own range.
enum FanHelper {
    private static var stopRequested: sig_atomic_t = 0

    static func run(uid: uid_t, parent: pid_t) -> Never {
        guard geteuid() == 0 else {
            FileHandle.standardError.write(Data("fan helper must run as root\n".utf8))
            exit(1)
        }
        guard let smc = SMC() else { exit(2) }
        signal(SIGTERM) { _ in FanHelper.stopRequested = 1 }
        signal(SIGINT) { _ in FanHelper.stopRequested = 1 }
        signal(SIGHUP) { _ in FanHelper.stopRequested = 1 }
        signal(SIGQUIT) { _ in FanHelper.stopRequested = 1 }
        signal(SIGPIPE, SIG_IGN)

        let path = FanHelperProtocol.socketPath(uid: uid)
        unlink(path)
        let listener = socket(AF_UNIX, SOCK_STREAM, 0)
        guard listener >= 0 else { exit(3) }
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutableBytes(of: &address.sun_path) { buffer in
            for (index, byte) in path.utf8.prefix(buffer.count - 1).enumerated() { buffer[index] = byte }
        }
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(listener, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        // Only the user who authorized the helper may talk to it.
        guard bound == 0, chown(path, uid, gid_t(0)) == 0, chmod(path, 0o600) == 0, listen(listener, 4) == 0 else {
            unlink(path)
            exit(4)
        }

        let coreKeys = smc.temperatureKeys().filter { $0.hasPrefix("Tp") || $0.hasPrefix("Te") || $0.hasPrefix("TC") }
        var manual = false
        /// Set when the helper took control back because the Mac got too hot.
        var overheated = false

        func restore() {
            for fan in 0..<FanCommand.maxFans { _ = smc.write("F\(fan)Md", 0) }
            _ = smc.write("Ftst", 0)
            manual = false
        }

        func quit() -> Never {
            restore()
            close(listener)
            unlink(path)
            exit(0)
        }

        /// Puts a fan under manual control. On Apple silicon the mode key is refused until the
        /// controller has been put in its test state, and that takes a moment to take effect.
        func makeManual(_ fan: Int) -> Bool {
            if smc.write("F\(fan)Md", 1) { return true }
            _ = smc.write("Ftst", 1)
            for _ in 0..<12 {
                usleep(500_000)
                if smc.write("F\(fan)Md", 1) { return true }
            }
            return false
        }

        func handle(_ command: FanCommand) -> String {
            switch command {
            case .ping:
                return overheated ? "ok overheated" : (manual ? "ok manual" : "ok auto")
            case .auto:
                restore()
                overheated = false
                return "ok auto"
            case .set(let index, let requested):
                let fans = smc.fans()
                guard let fan = fans.first(where: { $0.index == index }) else { return "error no such fan" }
                guard let rpm = FanLimits.clamp(requested, minimum: fan.minimum, maximum: fan.maximum) else { return "error fan range unknown" }
                let hottest = coreKeys.compactMap { smc.value($0) }.filter { $0 > 1 && $0 < 130 }.max()
                // Without a temperature to watch there is no guard, so there is no manual control.
                guard hottest != nil else { return "error no temperature sensor" }
                if FanLimits.mustReturnToAutomatic(hottestCore: hottest) { return "error too hot" }
                guard makeManual(index) else { return "error this Mac refused manual fan mode" }
                guard smc.write("F\(index)Tg", rpm) else {
                    restore()
                    return "error this Mac refused the fan speed"
                }
                manual = true
                overheated = false
                return "ok \(Int(rpm))"
            }
        }

        while true {
            if stopRequested != 0 { quit() }
            var descriptor = pollfd(fd: listener, events: Int16(POLLIN), revents: 0)
            let ready = poll(&descriptor, 1, 2_000)
            if ready > 0, descriptor.revents & Int16(POLLIN) != 0 {
                let client = accept(listener, nil, nil)
                if client >= 0 {
                    var peer: uid_t = 0, group: gid_t = 0
                    if getpeereid(client, &peer, &group) == 0, peer == uid {
                        var timeout = timeval(tv_sec: 2, tv_usec: 0)
                        setsockopt(client, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
                        var buffer = [UInt8](repeating: 0, count: 64)
                        let count = read(client, &buffer, buffer.count)
                        let line = count > 0 ? String(decoding: buffer.prefix(count), as: UTF8.self) : ""
                        let reply = (FanCommand(line: line).map(handle) ?? "error unknown command") + "\n"
                        _ = reply.withCString { write(client, $0, strlen($0)) }
                    }
                    close(client)
                }
            }
            // Watchdog: the app is gone, or the Mac is too hot to hold the fans back.
            if kill(parent, 0) != 0, errno == ESRCH { quit() }
            if manual {
                let hottest = coreKeys.compactMap { smc.value($0) }.filter { $0 > 1 && $0 < 130 }.max()
                if FanLimits.mustReturnToAutomatic(hottestCore: hottest) {
                    restore()
                    overheated = true
                }
            }
        }
    }
}
#endif
