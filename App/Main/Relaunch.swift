import AppKit

/// Quits the app and opens it again: after an update has replaced it, or for a change macOS reads
/// only at launch (the app's language).
enum Relaunch {
    /// Opens `app` once this process has exited, removing `leftover` (the replaced copy) after it.
    static func now(opening app: URL = Bundle.main.bundleURL, removing leftover: URL? = nil) {
        let script = """
            while kill -0 \(ProcessInfo.processInfo.processIdentifier) 2>/dev/null; do sleep 0.2; done
            open "$1"; [ -n "$2" ] && rm -rf "$2"
            """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", script, "relaunch", app.path, leftover?.path ?? ""]
        try? process.run()
        NSApp.terminate(nil)
    }
}
