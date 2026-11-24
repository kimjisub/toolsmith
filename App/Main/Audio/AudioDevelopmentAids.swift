#if TOOLSMITH_DEV
import AppKit
import CoreAudio
import ScreenCaptureKit
import SwiftUI
import ToolsmithKit

/// The sound control's development aids, run from the command line of a development build.
@MainActor enum AudioDevelopmentAids {
    /// `--play-tone <device UID> <Hz> <amplitude> <seconds>`: this process only plays a tone (see AudioSelfTest).
    nonisolated static func playToneIfAsked(_ arguments: [String]) {
        guard let index = arguments.firstIndex(of: "--play-tone"), index + 4 < arguments.count else { return }
        TonePlayer.run(uid: arguments[index + 1], frequency: Double(arguments[index + 2]) ?? 1_000,
                       amplitude: Double(arguments[index + 3]) ?? 0.2, seconds: Double(arguments[index + 4]) ?? 60)
    }

    /// Everything of this app on the display under the pointer, nothing of other apps. Needs Screen Recording.
    private static func captureOwnWindows(to url: URL) async {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            let pid = ProcessInfo.processInfo.processIdentifier
            let ours = content.windows.filter { $0.owningApplication?.processID == pid }
            guard let display = content.displays.first(where: { display in ours.contains { $0.frame.intersects(display.frame) } }) ?? content.displays.first else { return }
            let filter = SCContentFilter(display: display, including: ours)
            let configuration = SCStreamConfiguration()
            let bounds = ours.map(\.frame).reduce(CGRect.null) { $0.union($1) }.intersection(display.frame)
            configuration.sourceRect = bounds.offsetBy(dx: -display.frame.minX, dy: -display.frame.minY)
            configuration.width = Int(bounds.width * 2)
            configuration.height = Int(bounds.height * 2)
            configuration.showsCursor = false
            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
            let bitmap = NSBitmapImageRep(cgImage: image)
            try bitmap.representation(using: .png, properties: [:])?.write(to: url)
            print("screen shot: \(url.path) \(image.width)x\(image.height)")
        } catch {
            try? "screen shot failed: \(error)".write(to: url.appendingPathExtension("error.txt"), atomically: true, encoding: .utf8)
        }
    }

    /// The app whose line `--audio-demo` opens.
    static let demoExpandedApp = "com.apple.Music"

    /// `--audio-demo`: the sound screen on made-up devices, apps and levels in the app's language,
    /// for pictures without this Mac's own devices or apps. No route is built.
    static func showDemo(on mixer: AudioMixer) {
        let korean = Locale.app.language.languageCode == .korean
        let speakers = AudioDevice(id: 9_001, uid: "demo-speakers", name: korean ? "MacBook Pro 스피커" : "MacBook Pro Speakers",
                                   hasOutput: true, hasInput: false, transport: kAudioDeviceTransportTypeBuiltIn)
        let microphone = AudioDevice(id: 9_002, uid: "demo-microphone", name: korean ? "MacBook Pro 마이크" : "MacBook Pro Microphone",
                                     hasOutput: false, hasInput: true, transport: kAudioDeviceTransportTypeBuiltIn)
        let display = AudioDevice(id: 9_003, uid: "demo-display", name: korean ? "Studio Display 스피커" : "Studio Display Speakers",
                                  hasOutput: true, hasInput: false, transport: kAudioDeviceTransportTypeDisplayPort)
        func device(_ device: AudioDevice, volume: Double, rates: [Double]) -> SystemDeviceState {
            SystemDeviceState(device: device, volume: volume, canSetVolume: true, muted: false, canMute: true, balance: 0, canSetBalance: true,
                              sampleRate: rates.first, sampleRates: rates)
        }
        var music = AppAudioSettings(volume: 0.8, overdrive: 2, eq: EQPreset.bassBoost.settings)
        music.magicBoost = true
        let apps = [
            AudioMixer.DemoApp(key: "com.apple.Music", path: "/System/Applications/Music.app", settings: music, isPlaying: true, isFavorite: true),
            AudioMixer.DemoApp(key: "com.apple.podcasts", path: "/System/Applications/Podcasts.app", settings: AppAudioSettings(volume: 0.6, muted: true),
                               isPlaying: true, isFavorite: true),
            AudioMixer.DemoApp(key: "com.apple.Safari", path: "/Applications/Safari.app", settings: AppAudioSettings(volume: 0.45, outputUID: display.uid),
                               isPlaying: true, isFavorite: false),
        ]
        mixer.showDemo(devices: [speakers, microphone, display], output: device(speakers, volume: 0.62, rates: [48_000, 44_100]),
                       input: device(microphone, volume: 0.5, rates: [48_000]), effects: device(speakers, volume: 0.62, rates: []),
                       alertVolume: 0.7, apps: apps,
                       levels: [AudioMixer.outputKey: 0.55, "com.apple.Music": 0.42, "com.apple.podcasts": 0, "com.apple.Safari": 0.3])
    }

    /// Runs the aid `arguments` ask for, if any. Each one ends the app when it is done.
    static func run(_ arguments: [String]) {
        // Development aid: what the mixer reads on this Mac (devices, defaults, apps with sound), and
        // whether a tap and its device can be made here (made and taken apart again, never started), and quit.
        if arguments.contains("--print-audio") {
            for device in SystemAudio.devices() {
                print("device \(device.name) uid=\(device.uid) out=\(device.hasOutput) in=\(device.hasInput) transport=\(device.transport)")
            }
            for role in DeviceRole.allCases {
                let id = SystemAudio.defaultDevice(role)
                print("default \(role) id=\(id.map(String.init) ?? "-") volume=\(id.flatMap { SystemAudio.volume($0, role) }.map { String(format: "%.2f", $0) } ?? "-") settable=\(id.map { SystemAudio.canSetVolume($0, role) } ?? false) muted=\(id.flatMap { SystemAudio.isMuted($0, role) }.map(String.init) ?? "-")")
            }
            print("alert volume \(SystemAudio.alertVolume().map { String(format: "%.2f", $0) } ?? "-")")
            let groups = AudioApps.group(SystemAudio.processes(), ownPID: getpid()) { Bundle(path: $0)?.bundleIdentifier }
            for group in groups { print("app \(group.key) processes=\(group.processIDs) playing=\(group.isPlaying)") }
            print("own process object \(SystemAudio.ownProcessObject().map(String.init) ?? "-")")
            if let output = SystemAudio.defaultDevice(.output).flatMap({ id in SystemAudio.devices().first { $0.id == id } }) {
                print("route probe: \(TapRoute.probe(output: output))")
            }
            exit(0)
        }

        // Development aid: open the mixer on made-up settings (a temporary file, apps that are not
        // running, so nothing is tapped), draw its window into a picture, and quit.
        if let index = arguments.firstIndex(of: "--snapshot-mixer"), index + 1 < arguments.count {
            let file = FileManager.default.temporaryDirectory.appendingPathComponent("\(AppIdentity.compactName)-mixer-demo-\(UUID().uuidString)", isDirectory: true).appendingPathComponent("audio.json")
            let store = AudioConfigStore(fileURL: file)
            store.update { $0.favorites = ["com.apple.Music", "com.apple.Podcasts"] }
            store.updateApp("com.apple.Music") { $0.volume = 0.7; $0.overdrive = 2; $0.magicBoost = true; $0.eq = EQPreset.bassBoost.settings; $0.effects.append(.balance); $0.balance = -0.3 }
            store.updateApp("com.apple.Podcasts") { $0.muted = true; $0.outputUID = "demo-unplugged" }
            store.saveQuickConfig(name: "Meeting", system: SystemAudioState())
            let mixer = AudioMixer(store: store)
            // Meters would tap every app; a picture does not need them.
            mixer.metersEnabled = arguments.contains("--meters")
            mixer.setVisible(true)
            let panel = FloatingPanel()
            let expanded = arguments.firstIndex(of: "--expand").flatMap { $0 + 1 < arguments.count ? arguments[$0 + 1] : nil } ?? "com.apple.Music"
            let state = MixerViewState()
            panel.makeContent = { MixerView(mixer: mixer, state: state, expandedApp: expanded) }
            panel.attach()
            let visible = NSScreen.main?.visibleFrame ?? .zero
            panel.setFrame(NSRect(origin: NSPoint(x: visible.minX + 80, y: visible.maxY - panel.fittingSize.height - 20), size: panel.fittingSize), display: true)
            panel.orderFrontRegardless()
            // With --hold the panel stays up that many seconds after the picture, to be looked at or clicked.
            let hold = arguments.firstIndex(of: "--hold").flatMap { $0 + 1 < arguments.count ? Double(arguments[$0 + 1]) : nil } ?? 0
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                if let window = NSApp.windows.first(where: { $0.isVisible && $0 is FloatingPanel }) {
                    Snapshot.write(window, to: URL(fileURLWithPath: arguments[index + 1]))
                }
                // With --screen-shot <path> <seconds>, this app's own windows (the panel and any menu
                // opened on it by hand meanwhile) are captured from the screen after that long.
                if let shot = arguments.firstIndex(of: "--screen-shot"), shot + 2 < arguments.count {
                    // Asked at once, so the permission can be given before the moment of the picture.
                    if !CGPreflightScreenCaptureAccess() { CGRequestScreenCaptureAccess() }
                    let path = arguments[shot + 1]
                    DispatchQueue.main.asyncAfter(deadline: .now() + (Double(arguments[shot + 2]) ?? 20)) {
                        Task { await captureOwnWindows(to: URL(fileURLWithPath: path)) }
                    }
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + hold) { exit(0) }
            }
            return
        }

        // Development aid: checks the routes on real sound through BlackHole, writes the numbers to a file, and quits.
        if let index = arguments.firstIndex(of: "--audio-selftest"), index + 1 < arguments.count {
            let test = AudioSelfTest(resultPath: arguments[index + 1])
            Task { @MainActor in
                await test.run()
                exit(0)
            }
            return
        }
    }
}
#endif
