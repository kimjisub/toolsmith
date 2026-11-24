import SwiftUI
import ToolsmithKit

/// 화면 나누기 settings: the gap between tiled windows.
struct WindowsPane: View {
    @ObservedObject var settings: SettingsStore

    var body: some View {
        SettingsSection(title: "배치", footer: "나눈 창들 사이와 화면 가장자리에 두는 여백입니다.") {
            SliderRow(title: "창 사이 간격", value: settings.binding(\.windowGap), range: 0...24, step: 2) { $0 == 0 ? "없음" : "\(Int($0))pt" }
        }
    }
}
