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
            Permission(kind: .accessibility, title: String(localized: "Accessibility"), purpose: String(localized: "Moving and snapping windows, and pasting what you pick straight into the app you were using"),
                       symbol: "accessibility", color: Tile.blue, required: true) {
                AccessibilityPermission.prompt()
                AccessibilityPermission.openSystemSettings()
            },
            Permission(kind: .screenRecording, title: String(localized: "Screen Recording"), purpose: String(localized: "Screen capture, recording and text recognition. Takes effect after you reopen the app"),
                       symbol: "camera.viewfinder", color: Tile.pink, required: false) {
                ScreenCapturePermission.request()
                ScreenCapturePermission.openSystemSettings()
            },
            Permission(kind: .clipboard, title: String(localized: "Paste from Other Apps"), purpose: String(localized: "Keeping what you copy in clipboard history. The history stays on this Mac"),
                       symbol: "doc.on.clipboard", color: Tile.green, required: false, grant: nil,
                       instructions: String(localized: "System Settings → Privacy & Security → Paste from Other Apps: Allow")),
            Permission(kind: .microphone, title: String(localized: "Microphone"), purpose: String(localized: "Used only to record your voice with a screen recording"),
                       symbol: "mic.fill", color: Tile.orange, required: false) {
                // macOS asks only once; after a refusal the switch is in System Settings.
                if AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined {
                    AVCaptureDevice.requestAccess(for: .audio) { _ in }
                } else if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
                    NSWorkspace.shared.open(url)
                }
            },
            // macOS has no public way to ask whether this one is granted: the card says where it is.
            Permission(kind: .audioCapture, title: String(localized: "System Audio Recording"), purpose: String(localized: "Used in Sound to change one app’s volume, output and effects, and to measure its level. macOS asks the first time"),
                       symbol: "waveform", color: Tile.pink, required: false, grant: nil,
                       instructions: String(localized: "System Settings → Privacy & Security → Screen & System Audio Recording")),
            Permission(kind: .location, title: String(localized: "Location"), purpose: String(localized: "Used only to show the name of the connected Wi-Fi network. Your location itself is never read"),
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
