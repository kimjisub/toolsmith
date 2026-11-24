import CoreWLAN
import Darwin
import Foundation
import SystemConfiguration
import ToolsmithKit

/// Network traffic counters and what the Mac is connected to.
enum NetworkReader {
    /// Bytes received and sent on every real interface since it came up. Loopback is the Mac
    /// talking to itself; tunnels and Apple's peer links would count the same traffic twice.
    /// Read from the routing table's 64-bit counters: the 32-bit ones `getifaddrs` gives wrap at
    /// 4 GiB, which a fast link passes in under a minute.
    static func bytes() -> (received: UInt64, sent: UInt64) {
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]
        var length = 0
        guard sysctl(&mib, 6, nil, &length, nil, 0) == 0, length > 0 else { return (0, 0) }
        var buffer = [UInt8](repeating: 0, count: length)
        guard sysctl(&mib, 6, &buffer, &length, nil, 0) == 0 else { return (0, 0) }
        var received: UInt64 = 0, sent: UInt64 = 0
        buffer.withUnsafeBytes { raw in
            var offset = 0
            while offset + MemoryLayout<if_msghdr>.size <= length {
                let header = raw.loadUnaligned(fromByteOffset: offset, as: if_msghdr.self)
                guard header.ifm_msglen > 0 else { break }
                defer { offset += Int(header.ifm_msglen) }
                guard header.ifm_type == RTM_IFINFO2, offset + MemoryLayout<if_msghdr2>.size <= length else { continue }
                let info = raw.loadUnaligned(fromByteOffset: offset, as: if_msghdr2.self)
                var name = [CChar](repeating: 0, count: Int(IF_NAMESIZE))
                guard if_indextoname(UInt32(info.ifm_index), &name) != nil else { continue }
                let interface = String(cString: name)
                guard !["lo", "utun", "awdl", "llw", "bridge", "gif", "stf"].contains(where: interface.hasPrefix) else { continue }
                received += info.ifm_data.ifi_ibytes
                sent += info.ifm_data.ifi_obytes
            }
        }
        return (received, sent)
    }

    /// Every IPv4 and IPv6 address, skipping loopback and link-local ones.
    static func addresses() -> [InterfaceAddress] {
        var result: [InterfaceAddress] = []
        forEachInterface { name, address in
            guard let socket = address.pointee.ifa_addr else { return }
            let family = Int32(socket.pointee.sa_family)
            guard family == AF_INET || family == AF_INET6 else { return }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let length = socklen_t(family == AF_INET ? MemoryLayout<sockaddr_in>.size : MemoryLayout<sockaddr_in6>.size)
            guard getnameinfo(socket, length, &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 else { return }
            let text = String(cString: host)
            guard !name.hasPrefix("lo"), !text.hasPrefix("fe80"), !text.hasPrefix("169.254") else { return }
            result.append(InterfaceAddress(interface: name, address: text, isIPv6: family == AF_INET6))
        }
        return result
    }

    /// The interface the Mac sends internet traffic through ("en0").
    static func primaryInterface() -> String? {
        guard let store = SCDynamicStoreCreate(nil, AppIdentity.bundleID as CFString, nil, nil),
              let global = SCDynamicStoreCopyValue(store, "State:/Network/Global/IPv4" as CFString) as? [String: Any] else { return nil }
        return global["PrimaryInterface"] as? String
    }

    /// The Wi-Fi network's name. macOS only tells apps that have location permission; otherwise nil.
    static func wifiName() -> String? {
        CWWiFiClient.shared().interface()?.ssid()
    }

    static func isWiFi(_ interface: String) -> Bool {
        CWWiFiClient.shared().interfaceNames()?.contains(interface) ?? false
    }

    private static func forEachInterface(_ body: (String, UnsafeMutablePointer<ifaddrs>) -> Void) {
        var pointer: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&pointer) == 0, let first = pointer else { return }
        defer { freeifaddrs(pointer) }
        for interface in sequence(first: first, next: { $0.pointee.ifa_next }) {
            body(String(cString: interface.pointee.ifa_name), interface)
        }
    }
}

/// Asks Cloudflare which address the internet sees. The request goes to Cloudflare's public trace
/// page and carries nothing about the user; it is made only while the network details are open,
/// at most every few minutes.
@MainActor final class PublicAddressLookup: ObservableObject {
    @Published private(set) var address: PublicAddress?
    @Published private(set) var failed = false
    private var lastLookup: Date?
    private var lastInterface: String?
    private static let interval: TimeInterval = 300
    private static let url = URL(string: "https://www.cloudflare.com/cdn-cgi/trace")!

    /// Looks again when the last answer is old or the Mac switched networks.
    func refreshIfNeeded(interface: String?) {
        let stale = lastLookup.map { Date().timeIntervalSince($0) > Self.interval } ?? true
        guard stale || interface != lastInterface else { return }
        lastLookup = Date()
        lastInterface = interface
        Task {
            var request = URLRequest(url: Self.url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 6)
            request.setValue(AppIdentity.compactName, forHTTPHeaderField: "User-Agent")
            let text = try? await URLSession.shared.data(for: request).0
            let parsed = text.flatMap { PublicAddress.parse(trace: String(decoding: $0, as: UTF8.self)) }
            address = parsed
            failed = parsed == nil
        }
    }
}
