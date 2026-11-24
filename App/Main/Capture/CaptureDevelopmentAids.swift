import AppKit
import ToolsmithKit

#if TOOLSMITH_DEV
extension CaptureModule {
    /// Development flags this module answers (see CLAUDE.md, 빌드와 확인).
    func runDevelopmentAid(_ arguments: [String]) {
        // Development aid: draw every annotation kind onto a made-up picture, write it out, and quit.
        // Lets the renderer be looked at without opening a window.
        if let index = CommandLine.arguments.firstIndex(of: "--render-annotation-demo"), index + 1 < CommandLine.arguments.count {
            AnnotationDemo.render(to: URL(fileURLWithPath: CommandLine.arguments[index + 1]))
            exit(0)
        }

        // Development aid: record a small corner of the screen for two seconds, convert it to a
        // GIF too, print what came out, and quit. Checks the recorder end to end.
        if let index = CommandLine.arguments.firstIndex(of: "--record-demo"), index + 1 < CommandLine.arguments.count {
            let folder = URL(fileURLWithPath: CommandLine.arguments[index + 1])
            Task { @MainActor in
                let recorder = ScreenRecorder()
                do {
                    try await recorder.start(selection: CGRect(x: 40, y: 40, width: 320, height: 200), format: .video, systemAudio: false, microphone: false)
                    try await Task.sleep(for: .seconds(2))
                    let movie = try await recorder.stop()
                    let gif = folder.appendingPathComponent("demo.gif")
                    try await ScreenRecorder.makeGIF(from: movie, to: gif)
                    let size = { (url: URL) in (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0 }
                    print("movie bytes: \(size(movie)), gif bytes: \(size(gif))")
                    try? FileManager.default.moveItem(at: movie, to: folder.appendingPathComponent("demo.mp4"))
                } catch {
                    print("record demo failed: \((error as? CaptureError)?.message ?? error.localizedDescription)")
                }
                exit(0)
            }
            return
        }

        if arguments.contains("--annotation-editor-demo") {
            // Development aid: open the annotation editor on a made-up picture.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(AppIdentity.compactName)-annotation-demo.png")
                AnnotationDemo.render(to: url)
                if let image = NSImage(contentsOf: url)?.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                    AnnotationEditorWindow.show(CapturedImage(image: image, scale: 2), onCopy: { _ in }, onSave: { _ in })
                }
            }
        }
    }
}
#endif
