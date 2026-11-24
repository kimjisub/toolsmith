import AppKit
import ToolsmithKit

/// Runs the capture features: pick, shoot, then offer the result.
@MainActor final class CaptureCoordinator {
    private let overlay = SelectionOverlay()
    let cards = QuickCardPanel()
    private let sampler = NSColorSampler()
    private let recorder = ScreenRecorder()
    private let scroller = ScrollCapturer()
    private let recordingHUD = RecordingHUD()

    var settings: () -> Settings = { Settings() }
    /// One line for the user (a result or a reason something failed).
    var notify: (String) -> Void = { _ in }
    /// Called when the screen recording permission is missing.
    var onNeedsPermission: () -> Void = {}
    /// Opens the annotation editor for a capture.
    var onEdit: (CapturedImage, NSScreen?) -> Void = { _, _ in }

    init() {
        cards.onCopy = { [weak self] card in
            Self.copy(card.capture)
            self?.notify(String(localized: "Image copied."))
        }
        cards.onSave = { [weak self] card in self?.save(card.capture) }
        cards.onPin = { card in PinWindow.show(card.capture) }
        cards.onText = { [weak self] card in self?.copyText(of: card.capture) }
        cards.onEdit = { [weak self] card, screen in self?.onEdit(card.capture, screen) }
        recordingHUD.onStop = { [weak self] in self?.stopRecording() }
        // macOS ended the recording (its own stop control, a display unplugged): finish it as if the user had.
        recorder.onSystemStop = { [weak self] in self?.stopRecording() }
    }

    // MARK: Scrolling capture

    /// Pick an area on a scrollable page; it is scrolled and captured to the end (esc ends it early).
    func captureScrolling() {
        if scroller.isRunning { return scroller.finishEarly() }
        guard checkPermission() else { return }
        overlay.begin(.area, hint: String(localized: "Drag to select the area to scroll · esc to finish while capturing")) { [weak self] result in
            guard let self, case .area(let rect)? = result else { return }
            Task {
                // Let the overlay leave the screen first. Nothing of ours is shown while it runs,
                // because it would end up in the picture.
                try? await Task.sleep(for: .milliseconds(200))
                do {
                    let image = try await self.scroller.run(area: rect)
                    await self.deliver(image)
                    self.notify(String(localized: "Scrolling capture finished. \(Int(image.pointSize.height)) pt tall."))
                } catch {
                    self.report(error)
                }
            }
        }
    }

    // MARK: Recording

    var isRecording: Bool { recorder.isRecording }
    /// The recording has stopped but its file is still being finished or converted.
    private(set) var isFinishingRecording = false

    /// Drag out an area and record it. Running it again while recording stops.
    func recordArea(_ format: RecordingFormat) {
        if recorder.isRecording { return stopRecording() }
        guard checkPermission() else { return }
        overlay.begin(.area, hint: format == .gif ? String(localized: "Drag to select the area to record as GIF · esc to cancel") : String(localized: "Drag to select the area to record · esc to cancel")) { [weak self] result in
            guard case .area(let rect)? = result else { return }
            self?.beginRecording(selection: rect, format: format)
        }
    }

    func recordScreen() {
        if recorder.isRecording { return stopRecording() }
        guard checkPermission() else { return }
        beginRecording(selection: nil, format: .video)
    }

    private func beginRecording(selection: CGRect?, format: RecordingFormat) {
        let settings = self.settings()
        Task {
            // Let the overlay (or the launcher) leave the screen first.
            try? await Task.sleep(for: .milliseconds(200))
            do {
                try await self.recorder.start(selection: selection, format: format,
                                              systemAudio: settings.recordSystemAudio, microphone: settings.recordMicrophone)
                self.recordingHUD.show(area: self.recorder.area, startedAt: self.recorder.startedAt ?? Date(), isGIF: format == .gif)
            } catch {
                self.report(error)
            }
        }
    }

    func stopRecording() {
        guard recorder.isRecording else {
            notify(String(localized: "Not recording."))
            return
        }
        let format = recorder.format
        recordingHUD.hide()
        isFinishingRecording = true
        Task {
            defer { self.isFinishingRecording = false }
            let movie: URL
            do {
                movie = try await self.recorder.stop()
            } catch {
                return self.report(error)
            }
            let folder = Self.folder(self.settings())
            do {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                let ext = format == .gif ? "gif" : "mp4"
                let destination = CaptureFileName.uniqueURL(in: folder, name: CaptureFileName.name(date: Date(), ext: ext))
                if format == .gif {
                    self.notify(String(localized: "Converting to GIF…"))
                    try await ScreenRecorder.makeGIF(from: movie, to: destination)
                    try? FileManager.default.removeItem(at: movie)
                } else {
                    try FileManager.default.moveItem(at: movie, to: destination)
                }
                self.finishRecording(at: destination, note: String(localized: "Saved to \(folder.lastPathComponent) and copied the file"))
            } catch {
                self.rescue(movie, after: error)
            }
        }
    }

    /// The file itself goes to the clipboard, so ⌘V drops it into a chat or a mail.
    private func finishRecording(at file: URL, note: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([file as NSURL])
        notify("\(note): \(file.lastPathComponent)")
    }

    /// The recording exists but could not be converted or moved to its folder. The temporary
    /// folder is emptied at the next launch, so the movie goes to the Desktop instead.
    private func rescue(_ movie: URL, after error: Error) {
        guard FileManager.default.fileExists(atPath: movie.path),
              let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first else { return report(error) }
        let destination = CaptureFileName.uniqueURL(in: desktop, name: CaptureFileName.name(date: Date(), ext: "mp4"))
        do {
            try FileManager.default.moveItem(at: movie, to: destination)
            finishRecording(at: destination, note: String(localized: "Couldn’t save in the chosen format or folder, so the video was saved to the Desktop"))
        } catch {
            report(error)
        }
    }

    // MARK: Commands

    func captureArea() {
        guard checkPermission() else { return }
        overlay.begin(.area, hint: String(localized: "Drag to select an area · Space to pick a window · esc to cancel"), canSwitchMode: true) { [weak self] result in self?.shoot(result) }
    }

    func captureWindow() {
        guard checkPermission() else { return }
        overlay.begin(.window, hint: "", canSwitchMode: true) { [weak self] result in self?.shoot(result) }
    }

    func captureScreen() {
        guard checkPermission() else { return }
        run { try await Capturer.screenUnderPointer() }
    }

    /// Reads the text in an area and copies it.
    func recognizeText() {
        guard checkPermission() else { return }
        overlay.begin(.area, hint: String(localized: "Drag to select the area to read text from · esc to cancel")) { [weak self] result in
            guard let self, case .area(let rect)? = result else { return }
            Task {
                // Let the overlay leave the screen before the picture is taken.
                try? await Task.sleep(for: .milliseconds(80))
                do {
                    self.copyText(of: try await Capturer.area(rect))
                } catch {
                    self.report(error)
                }
            }
        }
    }

    /// Shows the system color loupe and copies the picked color.
    func pickColor() {
        sampler.show { [weak self] color in
            // The handler is not tied to the main actor: take the plain numbers out, then hop.
            guard let color = color?.usingColorSpace(.sRGB) else { return }
            let rgb = ToolsmithKit.RGBColor(unitRed: color.redComponent, green: color.greenComponent, blue: color.blueComponent)
            DispatchQueue.main.async { self?.copyColor(rgb) }
        }
    }

    private func copyColor(_ rgb: ToolsmithKit.RGBColor) {
        let text = settings().colorFormat.text(rgb)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        notify(String(localized: "Copied \(text)."))
    }

    /// Drag out a rectangle to read its size; the size is copied.
    func measure() {
        overlay.begin(.measure, hint: String(localized: "Drag to measure · esc to close")) { [weak self] result in
            guard let self, case .area(let rect)? = result else { return }
            let text = CaptureGeometry.sizeLabel(rect.size)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            self.notify(String(localized: "Copied \(text) (points)."))
        }
    }

    // MARK: Steps

    private func checkPermission() -> Bool {
        if ScreenCapturePermission.isGranted { return true }
        ScreenCapturePermission.request()
        notify(CaptureError.noPermission.message)
        onNeedsPermission()
        return false
    }

    private func shoot(_ result: SelectionResult?) {
        guard let result else { return }
        run {
            switch result {
            case .area(let rect): return try await Capturer.area(rect)
            case .window(let id, let frame): return try await Capturer.window(id: id, frame: frame)
            }
        }
    }

    private func run(_ capture: @escaping @MainActor () async throws -> CapturedImage) {
        Task {
            // Let the overlay (or the launcher) leave the screen first.
            try? await Task.sleep(for: .milliseconds(120))
            do {
                let image = try await capture()
                await self.deliver(image)
            } catch {
                self.report(error)
            }
        }
    }

    private func report(_ error: Error) {
        notify((error as? CaptureError)?.message ?? String(localized: "Couldn’t capture the screen: \(error.localizedDescription)"))
        if case CaptureError.noPermission = error { onNeedsPermission() }
    }

    private func copyText(of capture: CapturedImage) {
        Task {
            let text = await TextRecognizer.recognize(capture.image).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else {
                self.notify(String(localized: "No text found."))
                return
            }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            self.notify(String(localized: "Copied \(text.count) characters of text."))
        }
    }

    /// A new capture: to the clipboard (if the setting says so) and onto a preview card.
    private func deliver(_ image: CapturedImage) async {
        // Encoding a full-screen or scrolling capture takes a moment; keep it off the main thread and do it once.
        let png = await Task.detached(priority: .userInitiated) { image.pngData }.value
        if settings().captureCopiesToClipboard, let png { Self.copy(png: png) }
        cards.add(image, png: png)
    }

    static func copy(_ capture: CapturedImage) {
        if let data = capture.pngData { copy(png: data) }
    }

    /// PNG only: apps that take pictures read it, and an uncompressed copy beside it would cost tens of megabytes.
    /// Not marked as the app's own: a capture is kept nowhere else unless the user saves it,
    /// so the clipboard history is where it can be found again.
    static func copy(png: Data) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setData(png, forType: .png)
    }

    /// Saves to the capture folder. Returns where it went, or nil (after telling the user why).
    @discardableResult func save(_ capture: CapturedImage) -> URL? {
        let folder = Self.folder(settings())
        guard let data = capture.pngData else {
            notify(String(localized: "Couldn’t save the image."))
            return nil
        }
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let url = CaptureFileName.uniqueURL(in: folder, name: CaptureFileName.name(date: Date(), ext: "png"))
            try data.write(to: url, options: .atomic)
            notify(String(localized: "Saved to \(folder.lastPathComponent)."))
            return url
        } catch {
            notify(String(localized: "Couldn’t save: \(error.localizedDescription)"))
            return nil
        }
    }

    static func folder(_ settings: Settings) -> URL {
        if let path = settings.captureFolder, !path.isEmpty { return URL(fileURLWithPath: path) }
        return FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)[0]
    }
}

/// The capture features as launcher commands.
@MainActor final class CaptureCommandSource: CommandSource {
    static let section = CommandSection(id: "capture", title: String(localized: "Capture"), order: 3)
    static let stopID = "capture.record.stop"
    static let defaultHotkeys: [String: KeyCombo] = [
        "capture.area": KeyCombo(keyCode: 21, modifiers: [.option, .shift]),     // ⌥⇧4
        "capture.screen": KeyCombo(keyCode: 20, modifiers: [.option, .shift]),   // ⌥⇧3
    ]
    private let coordinator: CaptureCoordinator

    init(coordinator: CaptureCoordinator) { self.coordinator = coordinator }

    nonisolated func commands() -> [Command] {
        MainActor.assumeIsolated {
            let coordinator = self.coordinator
            @MainActor func command(_ id: String, _ title: LocalizedStringResource, _ symbol: String, keywords: [String], _ run: @escaping @MainActor () -> Void) -> Command {
                Command(id: id, localizedTitle: title, subtitle: nil, keywords: keywords + ["캡처", "capture", "screenshot", "스크린샷"],
                        section: Self.section, icon: .symbol(symbol), hotkeyID: id, run: run)
            }
            return [
                command("capture.area", "Capture Area", "rectangle.dashed", keywords: ["area", "부분"]) { coordinator.captureArea() },
                command("capture.window", "Capture Window", "macwindow", keywords: ["window"]) { coordinator.captureWindow() },
                command("capture.screen", "Capture Full Screen", "display", keywords: ["fullscreen", "전체"]) { coordinator.captureScreen() },
                command("capture.scroll", "Scrolling Capture", "arrow.up.and.down.text.horizontal", keywords: ["scroll", "긴 페이지", "전체 페이지", "long"]) { coordinator.captureScrolling() },
                command("capture.ocr", "Copy Text from Screen", "text.viewfinder", keywords: ["ocr", "text", "텍스트", "글자 읽기"]) { coordinator.recognizeText() },
                command("capture.color", "Pick Color", "eyedropper", keywords: ["color", "picker", "컬러", "스포이드", "색상"]) { coordinator.pickColor() },
                command("capture.measure", "Measure", "ruler", keywords: ["measure", "size", "ruler", "자", "치수"]) { coordinator.measure() },
                command("capture.record.area", "Record Area", "record.circle", keywords: ["record", "video", "영상", "동영상", "mp4"]) { coordinator.recordArea(.video) },
                command("capture.record.screen", "Record Full Screen", "record.circle.fill", keywords: ["record", "video", "영상", "동영상"]) { coordinator.recordScreen() },
                command("capture.record.gif", "Record Area as GIF", "photo.stack", keywords: ["record", "gif", "움짤"]) { coordinator.recordArea(.gif) },
                command(Self.stopID, "Stop Recording", "stop.circle", keywords: ["stop", "record", "정지", "중지"]) { coordinator.stopRecording() },
            ]
        }
    }
}
