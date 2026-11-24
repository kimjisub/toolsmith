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
                PanelHeader(title: "속도", symbol: "arrow.up.arrow.down")
                HStack(alignment: .top, spacing: Space.l) {
                    direction("arrow.down", MonitorStyle.primary, MonitorText.rate(monitor.snapshot.downloadRate), "다운로드")
                    direction("arrow.up", MonitorStyle.secondary, MonitorText.rate(monitor.snapshot.uploadRate), "업로드")
                }
                DualSparkline(down: monitor.downloadHistory.values, up: monitor.uploadHistory.values).frame(height: 44)
                TableRow(label: "최고 다운로드 속도", value: MonitorText.rate(monitor.peakDownload))
                TableRow(label: "최고 업로드 속도", value: MonitorText.rate(monitor.peakUpload))
            }
            Panel {
                PanelHeader(title: "연결", symbol: c.isWiFi ? "wifi" : "cable.connector")
                connectionRow
                ForEach(c.vpns, id: \.self) { TableRow(label: $0, value: "연결됨", dot: MonitorStyle.tertiary) }
                HStack(spacing: Space.s) {
                    Text("공용 IP").font(MonitorStyle.body).foregroundStyle(Ink.secondary)
                    Spacer(minLength: Space.s)
                    if let flag = publicAddress.address?.flag { Text(flag) }
                    Text(!monitor.allowsPublicAddressLookup() ? "꺼 둠" : publicAddress.address?.ip ?? (publicAddress.failed ? "알 수 없음" : "알아보는 중…"))
                        .font(MonitorStyle.number).textSelection(.enabled)
                }
                ForEach(c.addresses, id: \.address) { address in
                    TableRow(label: address.isIPv6 ? "IPv6" : "내부 IP", value: address.address)
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
            Text(c.isWiFi ? "Wi-Fi" : (c.interface == nil ? "연결 없음" : "유선")).font(MonitorStyle.body).foregroundStyle(Ink.secondary)
            Spacer(minLength: Space.s)
            if c.isWiFi {
                if let name = c.wifiName {
                    Text(name).font(MonitorStyle.number).lineLimit(1)
                } else if location.canAsk {
                    Button("이름 보기") { location.ask() }.buttonStyle(.link).font(.role(.secondary))
                        .help("macOS 는 위치 권한이 있는 앱에만 Wi-Fi 이름을 알려 줍니다")
                } else {
                    Text("이름은 위치 권한이 필요").font(.role(.detail)).foregroundStyle(MonitorStyle.quiet)
                }
            } else if let interface = c.interface {
                Text(interface).font(MonitorStyle.number)
            }
        }
    }

    private var processList: some View {
        Panel {
            HStack {
                PanelHeader(title: "많이 쓰는 앱", symbol: "list.number")
                Image(systemName: "arrow.down").font(.role(.caption, weight: .bold)).foregroundStyle(MonitorStyle.primary).frame(width: 72, alignment: .trailing)
                Image(systemName: "arrow.up").font(.role(.caption, weight: .bold)).foregroundStyle(MonitorStyle.secondary).frame(width: 72, alignment: .trailing)
            }
            if processes.network.isEmpty { Text("모으는 중…").font(.role(.secondary)).foregroundStyle(MonitorStyle.quiet) }
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
