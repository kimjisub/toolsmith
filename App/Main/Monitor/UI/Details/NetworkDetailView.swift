import CoreLocation
import SwiftUI
import ToolsmithKit

struct NetworkDetailView: View {
    @ObservedObject var monitor: MonitorModel
    @ObservedObject var processes: ProcessMonitor
    @ObservedObject var publicAddress: PublicAddressLookup
    @ObservedObject var selection: HistorySelection
    @StateObject private var location = LocationPermission()
    private var c: NetworkConnection { monitor.connection }

    var body: some View {
        VStack(spacing: Space.s) {
            HistoryBlock(topic: .network, selection: selection) {
                PanelHeader(title: String(localized: "Speed"), symbol: "arrow.up.arrow.down")
                HStack(alignment: .top, spacing: Space.l) {
                    direction("arrow.down", MonitorStyle.primary, MonitorText.rate(monitor.snapshot.downloadRate), String(localized: "Download"))
                    direction("arrow.up", MonitorStyle.secondary, MonitorText.rate(monitor.snapshot.uploadRate), String(localized: "Upload"))
                }
                DualSparkline(down: monitor.downloadHistory.values, up: monitor.uploadHistory.values).frame(height: 44)
                TableRow(label: String(localized: "Peak Download Speed"), value: MonitorText.rate(monitor.peakDownload))
                TableRow(label: String(localized: "Peak Upload Speed"), value: MonitorText.rate(monitor.peakUpload))
            }
            Panel {
                PanelHeader(title: String(localized: "Connection"), symbol: c.isWiFi ? "wifi" : "cable.connector")
                connectionRow
                ForEach(c.vpns, id: \.self) { TableRow(label: $0, value: String(localized: "Connected"), dot: MonitorStyle.tertiary) }
                HStack(spacing: Space.s) {
                    Text("Public IP").font(MonitorStyle.body).foregroundStyle(Ink.secondary)
                    Spacer(minLength: Space.s)
                    if let flag = publicAddress.address?.flag { Text(flag) }
                    Text(!monitor.allowsPublicAddressLookup() ? String(localized: "Turned off") : publicAddress.address?.ip ?? (publicAddress.failed ? String(localized: "Unknown") : String(localized: "Looking up…")))
                        .font(MonitorStyle.number).textSelection(.enabled)
                }
                ForEach(c.addresses, id: \.address) { address in
                    TableRow(label: address.isIPv6 ? "IPv6" : String(localized: "Local IP"), value: address.address)
                        .truncationMode(.middle).textSelection(.enabled)
                }
            }
            processList
        }
    }

    private func direction(_ symbol: String, _ color: Color, _ value: String, _ caption: String) -> some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            HStack(spacing: Space.xs) {
                Image(systemName: symbol).font(.role(.detail, weight: .bold)).foregroundStyle(color)
                Text(caption).font(.role(.detail)).foregroundStyle(MonitorStyle.quiet)
            }
            Text(value).font(.role(.title, weight: .light, design: .rounded)).monospacedDigit()
        }
    }

    @ViewBuilder private var connectionRow: some View {
        HStack(spacing: Space.s) {
            Text(c.isWiFi ? "Wi-Fi" : (c.interface == nil ? String(localized: "No connection") : String(localized: "Wired"))).font(MonitorStyle.body).foregroundStyle(Ink.secondary)
            Spacer(minLength: Space.s)
            if c.isWiFi {
                if let name = c.wifiName {
                    Text(name).font(MonitorStyle.number).lineLimit(1)
                } else if location.canAsk {
                    Button("Show Name") { location.ask() }.buttonStyle(.link).font(.role(.secondary))
                        .help("macOS tells only apps with Location access the Wi-Fi name")
                } else {
                    Text("Name needs Location access").font(.role(.detail)).foregroundStyle(MonitorStyle.quiet)
                }
            } else if let interface = c.interface {
                Text(interface).font(MonitorStyle.number)
            }
        }
    }

    private var processList: some View {
        Panel {
            HStack {
                PanelHeader(title: String(localized: "Top Apps"), symbol: "list.number")
                Image(systemName: "arrow.down").font(.role(.caption, weight: .bold)).foregroundStyle(MonitorStyle.primary).frame(width: 72, alignment: .trailing)
                Image(systemName: "arrow.up").font(.role(.caption, weight: .bold)).foregroundStyle(MonitorStyle.secondary).frame(width: 72, alignment: .trailing)
            }
            if processes.network.isEmpty { Text("Collecting…").font(.role(.secondary)).foregroundStyle(MonitorStyle.quiet) }
            ForEach(processes.network, id: \.entry.id) { item in
                HStack(spacing: Space.s) {
                    AppIcon(path: item.entry.path).frame(width: 18, height: 18)
                    Text(item.entry.name).font(MonitorStyle.body).lineLimit(1).truncationMode(.middle)
                    Spacer(minLength: Space.xs)
                    Text(MonitorText.rate(item.received)).font(MonitorStyle.number).frame(width: 72, alignment: .trailing)
                    Text(MonitorText.rate(item.sent)).font(MonitorStyle.number).frame(width: 72, alignment: .trailing)
                }
            }
        }
    }
}

/// Location permission, which macOS requires before it reveals the Wi-Fi network's name.
/// The app never asks for the location itself.
@MainActor final class LocationPermission: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var status: CLAuthorizationStatus
    private let manager = CLLocationManager()

    override init() {
        status = manager.authorizationStatus
        super.init()
        manager.delegate = self
    }

    var canAsk: Bool { status == .notDetermined }

    func ask() { manager.requestWhenInUseAuthorization() }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in self.status = status }
    }
}
