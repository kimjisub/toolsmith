import AVFoundation
import CoreLocation
import SwiftUI
import ToolsmithKit

/// A macOS permission the app uses, and why. Each is asked for only by the feature that needs it;
/// the first-run guide and the settings show them all in one place.
struct Permission: Identifiable {
    enum Kind: String { case accessibility, screenRecording, clipboard, microphone, audioCapture, location }

    let kind: Kind
    let title: String
    let purpose: String
    let symbol: String
    let color: Color
    /// Without it the app's core (launcher actions, window snapping) does not work.
    let required: Bool
    /// Opens the system's prompt or settings; nil when it can only be changed by hand.
    let grant: (@MainActor () -> Void)?
    /// What to do by hand when there is no button.
    var instructions: String?
    var id: String { kind.rawValue }

    @MainActor static func all(location: LocationPermission) -> [Permission] {
        [
            Permission(kind: .accessibility, title: "손쉬운 사용", purpose: "창 옮기기와 화면 나누기, 고른 항목을 쓰던 앱에 바로 붙여넣기",
                       symbol: "accessibility", color: Tile.blue, required: true) {
                AccessibilityPermission.prompt()
                AccessibilityPermission.openSystemSettings()
            },
            Permission(kind: .screenRecording, title: "화면 기록", purpose: "화면 캡처, 녹화, 글자 읽기. 허락한 뒤 앱을 다시 열어야 적용됩니다",
                       symbol: "camera.viewfinder", color: Tile.pink, required: false) {
                ScreenCapturePermission.request()
                ScreenCapturePermission.openSystemSettings()
            },
            Permission(kind: .clipboard, title: "다른 앱에서 붙여넣기", purpose: "복사한 것을 클립보드 기록에 남기기. 기록은 이 맥에만 있습니다",
                       symbol: "doc.on.clipboard", color: Tile.green, required: false, grant: nil,
                       instructions: "시스템 설정 → 개인정보 보호 및 보안 → 다른 앱에서 붙여넣기 에서 「허용」"),
            Permission(kind: .microphone, title: "마이크", purpose: "녹화에 목소리를 넣을 때만 씁니다",
                       symbol: "mic.fill", color: Tile.orange, required: false) {
                // macOS asks only once; after a refusal the switch is in System Settings.
                if AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined {
                    AVCaptureDevice.requestAccess(for: .audio) { _ in }
                } else if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
                    NSWorkspace.shared.open(url)
                }
            },
            // macOS has no public way to ask whether this one is granted: the card says where it is.
            Permission(kind: .audioCapture, title: "시스템 오디오 녹음", purpose: "소리 조절에서 앱 하나의 볼륨, 보낼 곳, 효과를 바꾸고 레벨을 잴 때 씁니다. 처음 쓸 때 macOS 가 묻습니다",
                       symbol: "waveform", color: Tile.pink, required: false, grant: nil,
                       instructions: "시스템 설정 → 개인정보 보호 및 보안 → 화면 및 시스템 오디오 녹음"),
            Permission(kind: .location, title: "위치", purpose: "연결된 Wi-Fi 이름을 보여 줄 때만 씁니다. 위치 자체는 읽지 않습니다",
                       symbol: "location.fill", color: Tile.teal, required: false) { location.ask() },
        ]
    }
}

/// Whether each permission is granted, looked at again every second while someone is watching:
/// permissions are granted in another app (System Settings), with no notice back.
@MainActor final class PermissionWatcher: ObservableObject {
    @Published private(set) var granted: Set<Permission.Kind> = []
    let location = LocationPermission()
    private var timer: Timer?

    init() { refresh() }

    func start() {
        refresh()
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.refresh() } }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    var permissions: [Permission] { Permission.all(location: location) }

    func refresh() {
        var now: Set<Permission.Kind> = []
        if AccessibilityPermission.isGranted { now.insert(.accessibility) }
        if ScreenCapturePermission.isGranted { now.insert(.screenRecording) }
        if ClipboardMonitor.canRead { now.insert(.clipboard) }
        if AVCaptureDevice.authorizationStatus(for: .audio) == .authorized { now.insert(.microphone) }
        let status = location.status
        if status == .authorizedAlways || status == .authorized { now.insert(.location) }
        if now != granted { granted = now }
    }
}
