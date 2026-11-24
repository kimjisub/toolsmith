import AVFoundation
import AppKit
import ImageIO
import ScreenCaptureKit
import ToolsmithKit
import UniformTypeIdentifiers

enum RecordingFormat {
    case video, gif
}

/// Records a display, or part of one, to a movie file.
@MainActor final class ScreenRecorder: NSObject {
    private var stream: SCStream?
    private var output: SCRecordingOutput?
    private var fileURL: URL?
    private var finished: CheckedContinuation<Void, Never>?
    private var failure: String?
    private var starting = false
    /// Counts stops, so a late timeout of one stop cannot end the wait of the next.
    private var stopGeneration = 0
    /// Called when the system, not the user, ended the stream.
    var onSystemStop: (() -> Void)?
    private(set) var startedAt: Date?
    private(set) var format: RecordingFormat = .video
    /// The recorded area in AppKit screen coordinates, for the outline shown while recording.
    private(set) var area: CGRect = .zero

    var isRecording: Bool { stream != nil || starting }

    /// `selection` is in AppKit screen coordinates; nil records the whole display the pointer is on.
    func start(selection: CGRect?, format: RecordingFormat, systemAudio: Bool, microphone: Bool) async throws {
        guard !isRecording else { return }
        guard ScreenCapturePermission.isGranted else { throw CaptureError.noPermission }
        // Claimed before the first await, so a second trigger cannot start a second stream.
        starting = true
        defer { starting = false }

        let pointer = NSEvent.mouseLocation
        let anchor = selection.map { CGPoint(x: $0.midX, y: $0.midY) } ?? pointer
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(anchor) }) ?? NSScreen.main,
              let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else {
            throw CaptureError.failed(String(localized: "There is no display."))
        }
        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        } catch {
            throw CaptureError.failed(error.localizedDescription)
        }
        guard let display = content.displays.first(where: { $0.displayID == displayID }) else { throw CaptureError.failed(String(localized: "That display could not be found.")) }

        // Our own windows (the stop button, the outline) stay out of the recording.
        let own = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }
        let filter = SCContentFilter(display: display, excludingApplications: own, exceptingWindows: [])

        let recorded = selection?.intersection(screen.frame) ?? screen.frame
        let source = RecordingGeometry.sourceRect(selection: recorded, displayFrame: screen.frame)
        let pixels = RecordingGeometry.pixelSize(points: source.size, scale: screen.backingScaleFactor)
        let configuration = SCStreamConfiguration()
        configuration.sourceRect = source
        configuration.width = pixels.width
        configuration.height = pixels.height
        configuration.showsCursor = true
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: format == .gif ? 30 : 60)
        configuration.capturesAudio = systemAudio && format == .video
        configuration.excludesCurrentProcessAudio = true
        configuration.captureMicrophone = microphone && format == .video

        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("\(AppIdentity.bundleID).recordings", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("\(UUID().uuidString).mp4")
        let recording = SCRecordingOutputConfiguration()
        recording.outputURL = url
        recording.outputFileType = .mp4
        recording.videoCodecType = .h264

        let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
        let output = SCRecordingOutput(configuration: recording, delegate: self)
        do {
            try stream.addRecordingOutput(output)
            try await stream.startCapture()
        } catch {
            throw CaptureError.failed(error.localizedDescription)
        }
        self.stream = stream
        self.output = output
        self.fileURL = url
        self.format = format
        self.area = recorded
        self.failure = nil
        self.startedAt = Date()
    }

    /// Stops and returns the movie file, or throws the reason there is none.
    func stop() async throws -> URL {
        guard let stream, let fileURL else { throw CaptureError.failed(String(localized: "Not recording.")) }
        self.stream = nil
        startedAt = nil
        stopGeneration += 1
        let generation = stopGeneration
        // The file is complete only once the output says so.
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            finished = continuation
            Task {
                try? await stream.stopCapture()
                // If the output never reports back, do not wait forever.
                try? await Task.sleep(for: .seconds(4))
                if self.stopGeneration == generation { self.resumeFinished() }
            }
        }
        output = nil
        self.fileURL = nil
        // What was recorded is kept even when the recording ended badly.
        let size = (try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? Int) ?? 0
        if size > 0 { return fileURL }
        try? FileManager.default.removeItem(at: fileURL)
        throw CaptureError.failed(failure ?? String(localized: "The recording file was not created."))
    }

    private func resumeFinished() {
        finished?.resume()
        finished = nil
    }

    private func failed(_ message: String) {
        failure = message
        // Still recording: end it now rather than let the user go on recording nothing.
        if stream != nil { onSystemStop?() }
        resumeFinished()
    }

    /// Turns a movie into a GIF beside it: fewer frames, capped width.
    nonisolated static func makeGIF(from movie: URL, to destination: URL) async throws {
        let asset = AVURLAsset(url: movie)
        let duration = try await asset.load(.duration).seconds
        guard let track = try await asset.loadTracks(withMediaType: .video).first else { throw CaptureError.failed(String(localized: "The video has no frames.")) }
        let natural = try await track.load(.naturalSize)
        let size = GIFPlan.size(width: Int(natural.width), height: Int(natural.height), maxWidth: GIFPlan.maxWidth)
        let times = GIFPlan.frameTimes(duration: duration, fps: GIFPlan.fps)

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: size.width, height: size.height)
        generator.requestedTimeToleranceBefore = CMTime(value: 1, timescale: 60)
        generator.requestedTimeToleranceAfter = CMTime(value: 1, timescale: 60)

        guard let target = CGImageDestinationCreateWithURL(destination as CFURL, UTType.gif.identifier as CFString, times.count, nil) else {
            throw CaptureError.failed(String(localized: "Couldn’t create the GIF file."))
        }
        CGImageDestinationSetProperties(target, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
        let frame = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 1.0 / Double(GIFPlan.fps)]] as CFDictionary
        var added = 0
        for time in times {
            guard let image = try? await generator.image(at: CMTime(seconds: time, preferredTimescale: 600)).image else { continue }
            CGImageDestinationAddImage(target, image, frame)
            added += 1
        }
        guard added > 0, CGImageDestinationFinalize(target) else { throw CaptureError.failed(String(localized: "Couldn’t convert to GIF.")) }
    }
}

extension ScreenRecorder: SCRecordingOutputDelegate, SCStreamDelegate {
    nonisolated func recordingOutputDidFinishRecording(_ recordingOutput: SCRecordingOutput) {
        Task { @MainActor in self.resumeFinished() }
    }

    nonisolated func recordingOutput(_ recordingOutput: SCRecordingOutput, didFailWithError error: Error) {
        let message = error.localizedDescription
        Task { @MainActor in self.failed(message) }
    }

    nonisolated func stream(_ stream: SCStream, didStopWithError error: Error) {
        let message = error.localizedDescription
        Task { @MainActor in
            // The system ended the stream (display unplugged, permission pulled): keep what was recorded.
            guard self.stream != nil else { return }
            self.failure = message
            self.onSystemStop?()
        }
    }
}

/// While recording: a small pill with the elapsed time and a stop button, and an outline around the area.
@MainActor final class RecordingHUD {
    private var pill: NSPanel?
    private var outline: NSPanel?
    private var timer: Timer?
    private let label = NSTextField(labelWithString: "00:00")
    var onStop: () -> Void = {}

    func show(area: CGRect, startedAt: Date, isGIF: Bool) {
        hide()
        guard let screen = NSScreen.screens.first(where: { $0.frame.intersects(area) }) ?? NSScreen.main else { return }

        // The outline, unless the whole display is being recorded.
        if area != screen.frame {
            let frame = area.insetBy(dx: -3, dy: -3)
            let panel = Self.panel(frame)
            panel.ignoresMouseEvents = true
            let view = NSView(frame: NSRect(origin: .zero, size: frame.size))
            view.wantsLayer = true
            view.layer?.borderColor = NSColor.systemRed.withAlphaComponent(0.9).cgColor
            view.layer?.borderWidth = 2
            view.layer?.cornerRadius = 4
            panel.contentView = view
            panel.orderFrontRegardless()
            outline = panel
        }

        let size = CGSize(width: 190, height: 40)
        let visible = screen.visibleFrame
        let panel = Self.panel(NSRect(x: visible.midX - size.width / 2, y: visible.minY + 24, width: size.width, height: size.height))
        let background = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
        background.material = .hudWindow
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 20
        background.layer?.masksToBounds = true

        let dot = NSView(frame: NSRect(x: 16, y: 15, width: 10, height: 10))
        dot.wantsLayer = true
        dot.layer?.backgroundColor = NSColor.systemRed.cgColor
        dot.layer?.cornerRadius = 5
        label.font = .monospacedDigitSystemFont(ofSize: 13, weight: .medium)
        label.textColor = .white
        label.frame = NSRect(x: 34, y: 11, width: 70, height: 18)
        let stop = NSButton(title: isGIF ? String(localized: "Stop GIF") : String(localized: "Finish"), target: self, action: #selector(stopPressed))
        stop.bezelStyle = .rounded
        stop.controlSize = .small
        stop.frame = NSRect(x: 100, y: 7, width: 80, height: 26)
        background.addSubview(dot)
        background.addSubview(label)
        background.addSubview(stop)
        panel.contentView = background
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.orderFrontRegardless()
        pill = panel

        label.stringValue = "00:00"
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.label.stringValue = RecordingGeometry.elapsedLabel(Date().timeIntervalSince(startedAt)) }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func hide() {
        timer?.invalidate()
        timer = nil
        pill?.orderOut(nil)
        outline?.orderOut(nil)
        pill = nil
        outline = nil
    }

    @objc private func stopPressed() { onStop() }

    private static func panel(_ frame: NSRect) -> NSPanel {
        let panel = NSPanel(contentRect: frame, styleMask: [.nonactivatingPanel, .borderless], backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isReleasedWhenClosed = false
        return panel
    }
}
