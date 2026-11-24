import SwiftUI
import ToolsmithKit

/// The entry point. Run with `--fan-helper <uid> <pid>` (as root, by the app itself) this
/// executable is the fan helper and never starts the app.
@main enum Main {
    static func main() {
        let arguments = CommandLine.arguments
        if let index = arguments.firstIndex(of: "--fan-helper") {
            #if TOOLSMITH_DEV
            if index + 2 < arguments.count, let uid = uid_t(arguments[index + 1]), let parent = pid_t(arguments[index + 2]) {
                FanHelper.run(uid: uid, parent: parent)
            }
            #endif
            // Asked to be the helper but cannot be: never fall through and run the app (as root).
            exit(64)
        }
        #if TOOLSMITH_DEV
        // The one aid that must not start the app: the sound self test's tone player is this
        // executable run as a plain process (a second copy of the app would take its shortcuts).
        AudioDevelopmentAids.playToneIfAsked(arguments)
        #endif
        // The app itself has no business running as root.
        guard geteuid() != 0 else { exit(64) }
        ToolsmithApp.main()
    }
}

struct ToolsmithApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    // The menu bar items and their windows are AppKit (see StatusBar); SwiftUI needs a scene.
    var body: some Scene {
        Settings { EmptyView() }
    }
}

/// Owns the app's objects from launch. A `@StateObject` on the App would not be created
/// until some view reads it, and the global shortcut must work before any view exists.
@MainActor final class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    @Published private(set) var environment: AppEnvironment?

    func applicationWillTerminate(_ notification: Notification) {
        environment?.terminate()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let environment = AppEnvironment()
        self.environment = environment
        environment.launch()

        // First launch: the guide. (Not when the app was started with a development flag.)
        if !environment.settings.settings.onboardingCompleted, CommandLine.arguments.count == 1 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { environment.onboarding.show() }
        }

        #if TOOLSMITH_DEV
        let arguments = CommandLine.arguments
        // Each running module answers its own flags.
        environment.modules.running.forEach { $0.runDevelopmentAid(arguments) }
        if arguments.contains("--show-onboarding") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { environment.onboarding.show() }
        }
        if let index = arguments.firstIndex(of: "--render-onboarding"), index + 1 < arguments.count {
            // Development aid: draw every page of the guide into pictures, and quit.
            for step in OnboardingStep.allCases {
                let model = OnboardingModel()
                model.step = step
                let renderer = ImageRenderer(content: OnboardingView(model: model, settings: environment.settings, onFinish: {})
                    .frame(width: OnboardingView.size.width, height: OnboardingView.size.height))
                renderer.scale = 2
                if let tiff = renderer.nsImage?.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff) {
                    try? bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: arguments[index + 1]).appendingPathComponent("onboarding-\(step.rawValue).png"))
                }
            }
            exit(0)
        }
        if let index = arguments.firstIndex(of: "--snapshot-settings"), index + 1 < arguments.count {
            // Development aid: open the settings window on every section in turn, draw the window
            // itself into pictures (no screen recording needed), and quit.
            let folder = URL(fileURLWithPath: arguments[index + 1])
            var panes = SettingsPane.all(environment.modules).makeIterator()
            func next() {
                guard let pane = panes.next() else { exit(0) }
                environment.openSettings(pane)
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                    if let window = NSApp.windows.first(where: { $0.isVisible && $0.windowController is SettingsWindowController }) {
                        Snapshot.write(window, to: folder.appendingPathComponent("settings-\(pane.rawValue).png"))
                    }
                    next()
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { next() }
        }
        if let index = arguments.firstIndex(of: "--render-menubar"), index + 1 < arguments.count {
            // Development aid: draw the menu bar as the saved layout shows it, on a dark menu bar, and quit.
            DispatchQueue.main.asyncAfter(deadline: .now() + 30) {
                let images = environment.menuBar.preview(environment.settings.settings.menuBarLayout).map(MenuBarPreview.flatten)
                let scale: CGFloat = 4, gap: CGFloat = 10
                let width = images.reduce(0) { $0 + $1.size.width } + gap * CGFloat(max(images.count - 1, 0))
                let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(width * scale) + 40, pixelsHigh: Int(MenuBarRenderer.height * scale) + 20,
                                              bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
                NSAppearance(named: .darkAqua)?.performAsCurrentDrawingAppearance {
                    NSColor(white: 0.12, alpha: 1).setFill()
                    NSRect(x: 0, y: 0, width: bitmap.pixelsWide, height: bitmap.pixelsHigh).fill()
                    var x: CGFloat = 20
                    for image in images {
                        image.draw(in: NSRect(x: x, y: 10, width: image.size.width * scale, height: image.size.height * scale))
                        x += (image.size.width + gap) * scale
                    }
                }
                NSGraphicsContext.restoreGraphicsState()
                try? bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: arguments[index + 1]))
                exit(0)
            }
        }
        if let index = arguments.firstIndex(of: "--snapshot-window"), index + 2 < arguments.count {
            // Development aid: after a few seconds, draw every visible window of this app into pictures, and quit.
            let folder = URL(fileURLWithPath: arguments[index + 1])
            let delay = Double(arguments[index + 2]) ?? 6
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                for (number, window) in NSApp.windows.filter({ $0.isVisible && $0.frame.width > 50 }).enumerated() {
                    Snapshot.write(window, to: folder.appendingPathComponent("window-\(number).png"))
                }
                exit(0)
            }
        }
        if let index = arguments.firstIndex(of: "--render-tokens"), index + 1 < arguments.count {
            // Development aid: the token sheet for the contributor guide, and quit.
            TokenSheet.render(to: URL(fileURLWithPath: arguments[index + 1]))
            exit(0)
        }
        if let index = arguments.firstIndex(of: "--show-panel"), index + 1 < arguments.count {
            // Development aid: open the menu bar panel on a screen ("monitor", "clipboard", "capture").
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { environment.openPanel(arguments[index + 1], below: nil) }
        }
        if arguments.contains("--show-settings") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                let pane = arguments.firstIndex(of: "--pane").flatMap { $0 + 1 < arguments.count ? SettingsPane(rawValue: arguments[$0 + 1]) : nil }
                environment.openSettings(pane)
            }
        }
        if let index = arguments.firstIndex(of: "--set-modules"), index + 2 < arguments.count {
            // Development aid: after a delay, switch modules ("clipboard=off,monitor=on") the way the features page does.
            let delay = Double(arguments[index + 2]) ?? 5
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                for pair in arguments[index + 1].split(separator: ",") {
                    let parts = pair.split(separator: "=").map(String.init)
                    guard parts.count == 2, let module = environment.modules.module(id: parts[0]) else { continue }
                    environment.settings.update { $0.modules.set(module.descriptor, on: parts[1] == "on") }
                }
            }
        }
        if arguments.contains("--show-launcher") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                environment.panel.show()
                if let index = arguments.firstIndex(of: "--query"), index + 1 < arguments.count {
                    environment.model.query = arguments[index + 1]
                }
                if arguments.contains("--ai-demo") {
                    environment.model.enterAIMode()
                    environment.ai.loadDemo()
                }
                // Show it a second time: the first show pays one-time costs a real key press never does.
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    guard arguments.contains("--measure") else { return }
                    environment.panel.hide()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { environment.panel.show() }
                }
            }
        }
        #endif
    }
}

#if TOOLSMITH_DEV
/// Draws a window's own views into a PNG: what the window shows, without screen recording.
@MainActor enum Snapshot {
    static func write(_ window: NSWindow, to url: URL) {
        guard let view = window.contentView, let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        // Glass is drawn by the window server, not the view: lay the picture on the glass's dark tint.
        let size = NSSize(width: bitmap.pixelsWide, height: bitmap.pixelsHigh)
        let flat = NSImage(size: size, flipped: false) { rect in
            NSColor(red: 0x1C / 255, green: 0x1E / 255, blue: 0x28 / 255, alpha: 1).setFill()
            rect.fill()
            bitmap.draw(in: rect)
            return true
        }
        guard let tiff = flat.tiffRepresentation, let output = NSBitmapImageRep(data: tiff) else { return }
        try? output.representation(using: .png, properties: [:])?.write(to: url)
    }
}
#endif
