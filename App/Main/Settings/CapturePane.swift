import AppKit
import SwiftUI
import ToolsmithKit

/// 캡처와 녹화 settings: where captures go, what happens after, and what a recording includes.
struct CapturePane: View {
    @ObservedObject var settings: SettingsStore

    var body: some View {
        SettingsLead(text: "화면의 영역, 창, 전체를 찍습니다. 찍은 그림은 왼쪽 아래에 떠서 복사, 저장, 고정, 글자 읽기를 고를 수 있습니다.")
        SettingsSection(title: "찍은 뒤") {
            SettingsRow(title: "저장 폴더", detail: (CaptureCoordinator.folder(settings.settings).path as NSString).abbreviatingWithTildeInPath) {
                if settings.settings.captureFolder != nil {
                    RowButton("데스크탑으로") { settings.update { $0.captureFolder = nil } }
                }
                RowButton("바꾸기…", action: chooseFolder)
            }
            ToggleRow(title: "찍자마자 클립보드에 복사", detail: "저장하지 않고 바로 붙여 넣을 수 있습니다", isOn: settings.binding(\.captureCopiesToClipboard))
            PickerRow(title: "색 표기", detail: "색 고르기로 고른 색을 복사할 때의 모양", selection: settings.binding(\.colorFormat),
                      options: ColorFormat.allCases, label: \.title)
        }
        SettingsSection(title: "녹화") {
            ToggleRow(title: "맥의 소리 넣기", detail: "영상 녹화에만 적용됩니다. GIF 에는 소리가 없습니다", isOn: settings.binding(\.recordSystemAudio))
            ToggleRow(title: "마이크 넣기", detail: "처음 켜고 녹화하면 macOS 가 마이크 권한을 묻습니다", isOn: settings.binding(\.recordMicrophone))
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "고르기"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        settings.update { $0.captureFolder = url.path }
    }
}
