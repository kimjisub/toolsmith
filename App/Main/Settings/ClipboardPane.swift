import AppKit
import SwiftUI
import ToolsmithKit
import UniformTypeIdentifiers

struct ClipboardPane: View {
    let clipboard: ClipboardModule
    @ObservedObject var settings: SettingsStore
    @State private var stats: (count: Int, bytes: Int) = (0, 0)
    @State private var confirmingClear = false
    /// History this large is worth a mention. Nothing is deleted because of it.
    private static let largeBytes = 5_000_000_000
    /// Searching reads every entry; past this many it starts to lag behind typing (about 0.1 s a key).
    private static let manyItems = 20_000

    private var sizeNote: String? {
        if stats.count > Self.manyItems { return "기록이 \(stats.count)개로 많이 쌓여 검색이 느려질 수 있습니다. 필요하면 보관 기간을 줄이거나 지울 수 있습니다." }
        if stats.bytes > Self.largeBytes { return "기록이 꽤 커졌습니다. 필요하면 보관 기간을 줄이거나 지울 수 있습니다." }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xxl) {
            SettingsLead(text: "⌥V 로 기록 띠를 열어 찾고 다시 붙입니다. 기록은 어디로도 보내지 않습니다.")
            if !ClipboardMonitor.canRead {
                Notice(text: "macOS 가 다른 앱에서 복사한 내용을 읽지 못하게 막고 있습니다. 시스템 설정 → 개인정보 보호 및 보안 → 다른 앱에서 붙여넣기 에서 \(AppIdentity.name) 을 「허용」 으로 바꿔 주세요.")
            }
            SettingsSection(title: "기록", footer: sizeNote) {
                ToggleRow(title: "기록 잠시 멈추기", detail: "켜 두는 동안 복사한 것은 쌓이지 않습니다", isOn: settings.binding(\.clipboardPaused))
                PickerRow(title: "보관 기간", detail: "고정한 것은 기간과 상관없이 남습니다", selection: Binding(get: { settings.settings.clipRetention }, set: { value in
                    settings.update { $0.clipRetention = value }
                    clipboard.purge()
                    refresh()
                }), options: ClipRetention.allCases, label: \.title)
                SettingsRow(title: "저장된 기록", detail: "\(stats.count)개 · \(ByteSize.text(stats.bytes))") {
                    RowButton("모두 지우기…", role: .destructive) { confirmingClear = true }
                }
            }
            SettingsSection(title: "기록하지 않을 앱", footer: "비밀번호 관리 앱처럼 이 앱들이 앞에 있을 때 복사한 것은 쌓이지 않습니다. 비밀번호로 표시된 복사는 앱과 상관없이 쌓이지 않습니다.") {
                ForEach(settings.settings.clipIgnoredApps, id: \.self) { bundleID in
                    ListRow(icon: AppIconCache.icon(bundleID: bundleID), title: Self.name(of: bundleID), subtitle: bundleID,
                            removeLabel: "\(Self.name(of: bundleID)) 빼기") {
                        settings.update { $0.clipIgnoredApps.removeAll { $0 == bundleID } }
                    }
                }
                ActionsRow { RowButton("앱 추가…", action: addApp) }
            }
        }
        .onAppear(perform: refresh)
        .confirmationDialog("클립보드 기록을 지울까요?", isPresented: $confirmingClear) {
            Button("고정한 것만 남기고 지우기", role: .destructive) { clipboard.clear(keepPinned: true); refresh() }
            Button("전부 지우기", role: .destructive) { clipboard.clear(keepPinned: false); refresh() }
            Button("취소", role: .cancel) {}
        } message: {
            Text("지운 기록은 되돌릴 수 없습니다.")
        }
    }

    private func refresh() { stats = clipboard.stats() }

    private static func name(of bundleID: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return bundleID }
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }

    private func addApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = true
        panel.prompt = "추가"
        guard panel.runModal() == .OK else { return }
        let ids = panel.urls.compactMap { Bundle(url: $0)?.bundleIdentifier }
        settings.update { current in
            for id in ids where !current.clipIgnoredApps.contains(id) { current.clipIgnoredApps.append(id) }
        }
    }
}
