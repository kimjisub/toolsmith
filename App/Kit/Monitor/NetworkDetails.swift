import Foundation

/// The address the internet sees, and the country it is in.
public struct PublicAddress: Equatable, Sendable {
    public let ip: String
    /// ISO country code ("KR").
    public let country: String?

    public init(ip: String, country: String?) {
        self.ip = ip
        self.country = country
    }

    /// Reads Cloudflare's trace page: "key=value" lines, among them "ip=" and "loc=".
    public static func parse(trace: String) -> PublicAddress? {
        var fields: [String: String] = [:]
        for line in trace.split(separator: "\n") {
            guard let equal = line.firstIndex(of: "=") else { continue }
            fields[String(line[..<equal])] = String(line[line.index(after: equal)...])
        }
        guard let ip = fields["ip"], !ip.isEmpty else { return nil }
        let country = fields["loc"].flatMap { $0.count == 2 ? $0.uppercased() : nil }
        return PublicAddress(ip: ip, country: country)
    }

    /// The country's flag, made of two regional indicator letters.
    public var flag: String? {
        guard let country, country.count == 2 else { return nil }
        let scalars = country.unicodeScalars.compactMap { UnicodeScalar(0x1F1E6 + $0.value - 65) }
        return scalars.count == 2 ? String(String.UnicodeScalarView(scalars)) : nil
    }
}

/// One address of one network interface.
public struct InterfaceAddress: Equatable, Sendable {
    public let interface: String
    public let address: String
    public let isIPv6: Bool

    public init(interface: String, address: String, isIPv6: Bool) {
        self.interface = interface
        self.address = address
        self.isIPv6 = isIPv6
    }
}

public enum VPNDetection {
    /// A tunnel interface with an address in 100.64.0.0/10 (carrier-grade NAT space) is Tailscale's;
    /// any other tunnel with an IPv4 address is some VPN. Tunnels without IPv4 are system plumbing.
    public static func names(tunnelAddresses: [InterfaceAddress]) -> [String] {
        let ipv4 = tunnelAddresses.filter { !$0.isIPv6 && $0.interface.hasPrefix("utun") }
        var names: [String] = []
        if ipv4.contains(where: { isCGNAT($0.address) }) { names.append("Tailscale") }
        if ipv4.contains(where: { !isCGNAT($0.address) }) { names.append("VPN") }
        return names
    }

    /// The physical interface behind the traffic. When a VPN is the system's primary interface,
    /// the connection worth naming is the Wi-Fi or Ethernet one underneath: the first "en"
    /// interface with an IPv4 address.
    public static func physicalInterface(primary: String?, addresses: [InterfaceAddress]) -> String? {
        if let primary, primary.hasPrefix("en") { return primary }
        return addresses.filter { !$0.isIPv6 && $0.interface.hasPrefix("en") }.map(\.interface).sorted().first ?? primary
    }

    static func isCGNAT(_ address: String) -> Bool {
        let parts = address.split(separator: ".").compactMap { Int($0) }
        return parts.count == 4 && parts[0] == 100 && (64...127).contains(parts[1])
    }
}
