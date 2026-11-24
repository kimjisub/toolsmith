import SwiftUI
import ToolsmithKit

struct MonitorPane: View {
    @ObservedObject var environment: AppEnvironment
    let monitor: MonitorModel
    @ObservedObject var settings: SettingsStore
    @State private var historyBytes: Int64 = 0
    @State private var confirmingClear = false

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xxl) {
            SettingsLead(text: "메뉴 막대의 수치를 누르면 대시보드가 열리고, 카드에 포인터를 올리면 자세한 내용이 옆에 열립니다.")
            SettingsSection(title: "메뉴 막대") {
                SettingsRow(title: "메뉴 막대에 보일 수치", detail: "CPU, 메모리, 디스크, 네트워크, 배터리, CPU 온도와 전력의 순서와 모양을 고릅니다") {
                    RowButton("메뉴 막대 설정") { environment.settingsPane = .menuBar }
                }
            }
            SettingsSection(title: "네트워크", footer: "켜 두면 네트워크 자세히 보기를 열 때 Cloudflare 의 공개 주소(www.cloudflare.com/cdn-cgi/trace)에 5분에 한 번까지 묻습니다. 보내는 것은 없고, Cloudflare 는 이 맥의 공인 IP 를 봅니다.") {
                ToggleRow(title: "공용 IP 주소 확인", detail: "인터넷이 보는 이 맥의 주소와 나라를 보여 줍니다", isOn: settings.binding(\.publicAddressLookup))
            }
            SettingsSection(title: "기록", footer: "1시간까지는 메모리에만 두고, 그보다 긴 기간은 1분 평균(3일 뒤부터는 10분 평균)을 28일 동안 이 맥에 둡니다.") {
                SettingsRow(title: "저장된 기록", detail: ByteSize.text(Int(historyBytes))) {
                    RowButton("지우기…", role: .destructive) { confirmingClear = true }
                }
            }
        }
        .onAppear(perform: refresh)
        .confirmationDialog("시스템 모니터 기록을 지울까요?", isPresented: $confirmingClear) {
            Button("지우기", role: .destructive) {
                monitor.clearHistory()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { refresh() }
            }
            Button("취소", role: .cancel) {}
        } message: { Text("그래프의 지난 기록이 사라집니다. 되돌릴 수 없습니다.") }
    }

    private func refresh() {
        historyBytes = DiskUsage.bytes(of: SettingsStore.supportDirectory.appendingPathComponent("monitor", isDirectory: true))
    }
}

/// How much room a file or folder takes on disk.
enum DiskUsage {
    static func bytes(of url: URL) -> Int64 {
        let keys: Set<URLResourceKey> = [.totalFileAllocatedSizeKey, .isRegularFileKey]
        guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: Array(keys)) else {
            return Int64((try? url.resourceValues(forKeys: keys))?.totalFileAllocatedSize ?? 0)
        }
        var total: Int64 = 0
        for case let file as URL in enumerator {
            guard let values = try? file.resourceValues(forKeys: keys), values.isRegularFile == true else { continue }
            total += Int64(values.totalFileAllocatedSize ?? 0)
        }
        return total
    }
}
