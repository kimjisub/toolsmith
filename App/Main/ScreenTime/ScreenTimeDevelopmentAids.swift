import AppKit
import SwiftUI
import ToolsmithKit

#if TOOLSMITH_DEV
extension ScreenTimeModule {
    /// Development flags this module answers (see CLAUDE.md, 빌드와 확인).
    func runDevelopmentAid(_ arguments: [String]) {
        // Development aid: draw the screen time report from made-up numbers into a picture, and quit.
        if let index = CommandLine.arguments.firstIndex(of: "--render-screentime-demo"), index + 1 < CommandLine.arguments.count {
            var report = ScreenTimeReport()
            report.apps = [("com.tinyspeck.slackmacgap", "Slack", 3_900.0), ("com.google.Chrome", "Google Chrome", 3_100), ("com.apple.dt.Xcode", "Xcode", 2_400),
                           ("com.apple.Notes", "메모", 700), ("com.apple.finder", "Finder", 200)].map { AppUsage(bundleID: $0.0, name: $0.1, seconds: $0.2) }
            report.hourly = [0, 0, 0, 0, 0, 0, 0, 0, 0, 1_500, 2_400, 1_800, 300, 1_200, 2_100, 1_000, 0, 0, 0, 0, 0, 0, 0, 0]
            report.week = [21_000, 18_500, 0, 0, 24_000, 19_800, 10_300]
            // The empty report is what the pane shows for an instant before it loads: it must draw too.
            _ = ImageRenderer(content: ScreenTimeContent(report: ScreenTimeReport())).nsImage
            let renderer = ImageRenderer(content: ScreenTimeContent(report: report).padding(Space.xxl).frame(width: 570).background(Surface.ground).environment(\.colorScheme, .dark))
            renderer.scale = 2
            if let tiff = renderer.nsImage?.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff) {
                try? bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: CommandLine.arguments[index + 1]))
            }
            exit(0)
        }
    }
}
#endif
