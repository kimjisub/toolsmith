import AppKit
import SwiftUI
import ToolsmithKit

/// What the app keeps, where it goes, and the way to delete it. Everything is listed, nothing summarised.
struct PrivacyPane: View {
    @ObservedObject var environment: AppEnvironment
    @ObservedObject var modules: ModuleManager
    @ObservedObject var settings: SettingsStore
    @State private var sizes: [String: Int64] = [:]

    private static let folders: [(key: String, title: String, detail: String, pane: SettingsPane?)] = [
        ("clipboard", "클립보드 기록", "복사한 글자와 그림. 비밀번호로 표시된 복사와 고른 앱의 복사는 남기지 않습니다", .clipboard),
        ("screentime", "사용 시간", "앞에 있던 앱과 시간. 90일 뒤 지웁니다", .screenTime),
        ("monitor", "시스템 모니터 기록", "CPU, 메모리, 네트워크, 전력 같은 숫자의 1분 평균. 28일 뒤 지웁니다", .monitor),
    ]

    var body: some View {
        SettingsPage(title: "개인정보와 저장 공간", lead: "\(AppIdentity.name) 이 이 맥에 남기는 것과 밖으로 보내는 것 전부입니다. 기록을 어느 서버로도 보내지 않습니다.") {
            SettingsSection(title: "이 맥에 남기는 것", footer: "모두 \((SettingsStore.supportDirectory.path as NSString).abbreviatingWithTildeInPath) 에 있고, 이 맥의 사용자만 읽을 수 있습니다.") {
                ForEach(Self.folders, id: \.key) { folder in
                    SettingsRow(title: folder.title, detail: "\(folder.detail) · \(ByteSize.text(Int(sizes[folder.key] ?? 0)))") {
                        // A switched-off feature has no page to manage it on; its data is still listed.
                        if let pane = folder.pane, case .module(let id) = pane, modules.isEnabled(id) {
                            RowButton("관리") { environment.settingsPane = pane }
                        }
                    }
                }
                SettingsRow(title: "OpenRouter 키", detail: KeyStore.hasSavedKey ? "이 맥의 키체인에 있습니다" : "없습니다") {
                    if modules.isEnabled(AIModule.descriptor.id) { RowButton("관리") { environment.settingsPane = .ai } }
                }
                SettingsRow(title: "설정", detail: "단축키와 이 화면의 선택들") {
                    RowButton("Finder 에서 보기") { NSWorkspace.shared.activateFileViewerSelecting([SettingsStore.supportDirectory]) }
                }
            }
            SettingsSection(title: "밖으로 보내는 것") {
                SettingsRow(title: "AI 검색 → OpenRouter", detail: "입력창에서 AI 에게 물을 때만, 그 질문을 보냅니다. 답은 저장하지 않습니다")
                ToggleRow(title: "공용 IP 확인 → Cloudflare", detail: "네트워크 자세히 보기를 열 때만, 5분에 한 번까지. 보내는 내용은 없습니다",
                          isOn: settings.binding(\.publicAddressLookup))
                ToggleRow(title: "사용 시간 기록", detail: "보내지는 않습니다. 끄면 앞에 있는 앱을 기록하지 않습니다", isOn: settings.moduleBinding(ScreenTimeModule.descriptor))
            }
        }
        .onAppear(perform: refresh)
    }

    private func refresh() {
        let base = SettingsStore.supportDirectory
        DispatchQueue.global(qos: .utility).async {
            var result: [String: Int64] = [:]
            for folder in Self.folders { result[folder.key] = DiskUsage.bytes(of: base.appendingPathComponent(folder.key, isDirectory: true)) }
            DispatchQueue.main.async { sizes = result }
        }
    }
}
