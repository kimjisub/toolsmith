import SwiftUI
import ToolsmithKit

/// The sound control's groups on its settings page. The page's header, shortcuts and permissions
/// are drawn by the settings window around them.
struct AudioSettingsGroups: View {
    @ObservedObject var mixer: AudioMixer
    let open: () -> Void

    var body: some View {
        if mixer.loadFailed {
            Notice(text: "저장된 소리 설정 파일을 읽지 못해 audio.broken.json 으로 옮겨 두었습니다. 지금은 기본값으로 동작합니다.")
        }
        SettingsSection(title: "열기", footer: "메뉴 막대의 스피커를 누르거나 입력창에서 「소리 조절 열기」 로 엽니다. 스피커를 메뉴 막대에 둘지, 볼륨 숫자를 함께 보일지는 「메뉴 막대」 칸에서 정합니다. 입력창에는 출력, 입력 장치를 바로 바꾸는 명령과 저장한 Quick Config 도 나옵니다.") {
            SettingsRow(title: "소리 조절") { RowButton("열기", action: open) }
        }
        SettingsSection(title: "앱 소리를 바꾸는 방법", footer: "손대지 않은 앱은 macOS 가 평소대로 소리를 냅니다. 앱 하나의 볼륨, 보낼 곳, 효과를 바꾸면 그 앱의 소리만 받아 와서 바꾼 뒤 고른 장치로 냅니다. 이 기능을 끄거나 앱을 닫으면 모든 앱이 평소대로 돌아옵니다. 허락하지 않으면 바꾼 앱의 소리가 들리지 않으니, 그때는 허락하거나 그 앱의 설정을 되돌립니다.") {
            SettingsRow(title: "바꾼 앱", detail: mixer.configuration.apps.isEmpty ? "없음" : "\(mixer.configuration.apps.count)개") {
                RowButton("모두 되돌리기", role: .destructive) { mixer.configuration.apps.keys.forEach(mixer.resetApp) }
            }
            SettingsRow(title: "Quick Configs", detail: mixer.configuration.quickConfigs.isEmpty ? "없음" : mixer.configuration.quickConfigs.map(\.name).joined(separator: ", "))
            SettingsRow(title: "출력 묶음", detail: mixer.configuration.outputGroups.isEmpty ? "없음" : mixer.configuration.outputGroups.map(\.name).joined(separator: ", "))
        }
    }
}
