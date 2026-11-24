import AppKit
import ScreenCaptureKit
import ToolsmithKit
@preconcurrency import Vision

enum ScreenCapturePermission {
    static var isGranted: Bool { CGPreflightScreenCaptureAccess() }

    /// Asks the system to show its permission dialog (it does so once per app).
    static func request() { _ = CGRequestScreenCaptureAccess() }

    static func openSystemSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }
}

/// A picture taken of the screen. Immutable, so it may cross threads.
struct CapturedImage: @unchecked Sendable {
    let image: CGImage
    /// Pixels per point, so the picture can be shown at the size it had on screen.
    let scale: CGFloat

    var pointSize: CGSize { CGSize(width: CGFloat(image.width) / scale, height: CGFloat(image.height) / scale) }

    var pngData: Data? {
        let bitmap = NSBitmapImageRep(cgImage: image)
        bitmap.size = pointSize
        return bitmap.representation(using: .png, properties: [:])
    }

    var nsImage: NSImage { NSImage(cgImage: image, size: pointSize) }
}

enum CaptureError: Error {
    case noPermission, failed(String)

    var message: String {
        switch self {
        case .noPermission: return "화면을 찍으려면 화면 기록 권한이 필요합니다. 설정의 캡처에서 허락해 주세요."
        case .failed(let reason): return "화면을 찍지 못했습니다: \(reason)"
        }
    }
}

@MainActor enum Capturer {
    /// `rect` is in AppKit screen coordinates.
    static func area(_ rect: CGRect) async throws -> CapturedImage {
        guard ScreenCapturePermission.isGranted else { throw CaptureError.noPermission }
        guard let primary = NSScreen.screens.first else { throw CaptureError.failed("화면이 없습니다") }
        // Preferred: the display's content without our own windows (preview cards, pinned captures).
        let center = CGPoint(x: rect.midX, y: rect.midY)
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(center) }),
           let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID,
           let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true),
           let display = content.displays.first(where: { $0.displayID == displayID }) {
            let own = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }
            let source = RecordingGeometry.sourceRect(selection: rect, displayFrame: screen.frame)
            let scale = screen.backingScaleFactor
            let configuration = SCStreamConfiguration()
            configuration.sourceRect = source
            configuration.width = max(1, Int((source.width * scale).rounded()))
            configuration.height = max(1, Int((source.height * scale).rounded()))
            configuration.showsCursor = false
            configuration.captureResolution = .best
            let filter = SCContentFilter(display: display, excludingApplications: own, exceptingWindows: [])
            if let image = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration) {
                return CapturedImage(image: image, scale: scale)
            }
        }
        let flipped = CaptureGeometry.topLeftOrigin(rect, primaryHeight: primary.frame.maxY)
        do {
            let image = try await SCScreenshotManager.captureImage(in: flipped)
            return CapturedImage(image: image, scale: max(1, CGFloat(image.width) / max(1, rect.width)))
        } catch {
            throw CaptureError.failed(error.localizedDescription)
        }
    }

    /// The whole display the pointer is on.
    static func screenUnderPointer() async throws -> CapturedImage {
        let pointer = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(pointer) }) ?? NSScreen.main else {
            throw CaptureError.failed("화면이 없습니다")
        }
        return try await area(screen.frame)
    }

    /// One window by itself, without what is behind or in front of it. `frame` is in capture coordinates.
    static func window(id: CGWindowID, frame: CGRect) async throws -> CapturedImage {
        guard ScreenCapturePermission.isGranted else { throw CaptureError.noPermission }
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
            guard let window = content.windows.first(where: { $0.windowID == id }) else {
                throw CaptureError.failed("그 창을 찾지 못했습니다")
            }
            let filter = SCContentFilter(desktopIndependentWindow: window)
            let scale = CGFloat(filter.pointPixelScale)
            let configuration = SCStreamConfiguration()
            configuration.width = Int(filter.contentRect.width * scale)
            configuration.height = Int(filter.contentRect.height * scale)
            configuration.showsCursor = false
            configuration.ignoreShadowsSingleWindow = false
            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
            return CapturedImage(image: image, scale: scale)
        } catch let error as CaptureError {
            throw error
        } catch {
            throw CaptureError.failed(error.localizedDescription)
        }
    }
}

enum TextRecognizer {
    /// The text in a picture, top to bottom. Korean and English.
    static func recognize(_ image: CGImage) async -> String {
        await withCheckedContinuation { (continuation: CheckedContinuation<String, Never>) in
            // The request's handler and a thrown error could both report; answer only once.
            let lock = NSLock()
            var answered = false
            func answer(_ text: String) {
                lock.lock()
                defer { lock.unlock() }
                guard !answered else { return }
                answered = true
                continuation.resume(returning: text)
            }
            let request = VNRecognizeTextRequest { request, _ in
                let lines = (request.results as? [VNRecognizedTextObservation] ?? []).compactMap { $0.topCandidates(1).first?.string }
                answer(lines.joined(separator: "\n"))
            }
            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["ko-KR", "en-US"]
            request.usesLanguageCorrection = true
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try VNImageRequestHandler(cgImage: image).perform([request])
                } catch {
                    answer("")
                }
            }
        }
    }
}
