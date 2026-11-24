import SwiftUI
import ToolsmithKit

struct BatteryPane: View {
    @ObservedObject var charge: ChargeController

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xxl) {
            SettingsLead(text: "배터리를 오래 쓰려면 늘 100% 로 두지 않는 것이 좋습니다. 충전을 일정 수준에서 멈춥니다.")
            if charge.canControl {
                SettingsSection(title: "충전 제한") {
                    TimelineView(.periodic(from: .now, by: 5)) { _ in
                        ContentRow { ChargeControls(charge: charge, battery: BatteryReader.battery()) }
                    }
                }
            }
            if charge.state == .system {
                if charge.helperRegistered {
                    SettingsSection(title: "예전 도우미", footer: "이 맥은 macOS 의 충전 제한을 쓰므로 예전에 설치한 충전 도우미가 필요 없습니다. 제거하면 도우미가 바꿔 둔 충전 설정을 원래대로 돌려놓고 지웁니다.") {
                        SettingsRow(title: "설치되어 있습니다", detail: "더 이상 쓰지 않습니다") {
                            RowButton("제거", role: .destructive) { charge.uninstall() }.disabled(charge.busy)
                        }
                    }
                }
            } else {
                SettingsSection(title: "도우미", footer: "이 맥의 macOS 에는 충전 제한이 없어(macOS 26.4 이상 애플 실리콘 맥에 있습니다) 맥의 전원 관리 칩(SMC)에 직접 값을 씁니다. 이는 관리자 권한이 필요합니다. 「설치」 를 누르면 \(AppIdentity.name) 안에 든 작은 도우미(ToolsmithHelper)가 시스템의 백그라운드 항목으로 등록되고, 시스템 설정 → 일반 → 로그인 항목에서 허용하면 관리자 권한으로 돕니다. 도우미는 충전 말고는 아무것도 하지 않고 \(AppIdentity.name) 의 요청만 받습니다. 「제거」 를 누르면 충전을 원래대로 돌려놓고 지웁니다.") {
                    SettingsRow(title: stateTitle, detail: stateDetail) {
                        actions
                    }
                }
            }
        }
        .onAppear { charge.refresh() }
    }

    @ViewBuilder private var actions: some View {
        switch charge.state {
        case .notInstalled:
            RowButton("설치") { charge.install() }
        case .needsApproval:
            RowButton("로그인 항목 열기") { charge.openLoginItems() }
            RowButton("다시 확인") { charge.refresh() }
        case .running, .unsupportedMac, .failed:
            RowButton("제거", role: .destructive) { charge.uninstall() }.disabled(charge.busy)
        case .unsupportedBuild, .noBattery, .system:
            EmptyView()
        }
    }

    private var stateTitle: String {
        switch charge.state {
        case .system: return "필요 없습니다"
        case .unsupportedBuild: return "이 빌드에서는 쓸 수 없습니다"
        case .noBattery: return "배터리가 없는 맥입니다"
        case .notInstalled: return "설치되어 있지 않습니다"
        case .needsApproval: return "허용을 기다립니다"
        case .running: return "동작 중"
        case .unsupportedMac: return "이 맥은 지원하지 않습니다"
        case .failed: return "문제가 있습니다"
        }
    }

    private var stateDetail: String {
        switch charge.state {
        case .system: return "macOS 의 충전 제한을 씁니다"
        case .unsupportedBuild: return "도우미는 개발자의 Developer ID 로 서명한 배포 빌드에서만 설치됩니다"
        case .noBattery: return "충전 제한은 맥북에서만 의미가 있습니다"
        case .notInstalled: return "설치하면 관리자 암호나 허용을 한 번 묻습니다"
        case .needsApproval: return "시스템 설정 → 일반 → 로그인 항목 에서 \(AppIdentity.name) 을 켜 주세요"
        case .running:
            guard let status = charge.status else { return "" }
            return status.output.inhibit ? "충전 멈춤" : status.output.adapterOff ? "배터리로 쓰는 중" : "평소대로 충전"
        case .unsupportedMac: return "이 맥의 전원 관리 칩에서 충전을 다룰 방법을 찾지 못했습니다"
        case .failed(let message): return message
        }
    }
}
