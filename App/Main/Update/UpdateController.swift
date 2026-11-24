import AppKit
import Foundation
import ToolsmithKit
import UserNotifications

/// Keeps the app current from GitHub releases: checks at launch and every six hours, downloads and
/// verifies a newer build, and swaps it in when no screen recording is running. The About page
/// shows how the last check went. When a release fails to download or install, a notification
/// says so and automatic checks stop fetching that release; checking by hand tries it again.
@MainActor final class UpdateController: ObservableObject {
    struct LastCheck: Codable, Equatable {
        let at: Date
        let message: String
    }

    /// The source repository; each tagged release carries the DMG and release.json.
    static let repository = AppIdentity.updateRepository
    static let interval: TimeInterval = 6 * 3600
    private static let lastCheckKey = "updateLastCheck"
    private static let failedReleaseKey = "updateFailedRelease"

    @Published private(set) var isChecking = false
    @Published private(set) var lastCheck: LastCheck?

    private let settings: SettingsStore
    private let isBusy: () -> Bool
    private var timer: Timer?
    /// A verified build waiting for the screen recording to end.
    private var pending: (release: AppRelease, app: URL)?

    /// `isBusy` says when replacing the app would cut something off (a screen recording).
    init(settings: SettingsStore, isBusy: @escaping () -> Bool) {
        self.settings = settings
        self.isBusy = isBusy
        lastCheck = UserDefaults.standard.data(forKey: Self.lastCheckKey).flatMap { try? JSONDecoder().decode(LastCheck.self, from: $0) }
    }

    static var currentVersion: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0" }
    static var currentBuild: Int { Int(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "") ?? 0 }

    /// Only released builds (signed by the team) update themselves; a development build would be
    /// replaced by the latest release.
    var canUpdate: Bool { CodeSignature.isSignedByTeam }

    func launch() {
        guard canUpdate else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 20) { [weak self] in
            guard let self, self.settings.settings.automaticUpdates else { return }
            Task { await self.check(automatic: true) }
        }
        let timer = Timer(timeInterval: Self.interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.settings.settings.automaticUpdates else { return }
                Task { await self.check(automatic: true) }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// `automatic` is the launch and six-hourly check; 「지금 확인」 is not.
    func check(automatic: Bool = false) async {
        guard !isChecking else { return }
        guard canUpdate else {
            record("개발 빌드는 업데이트를 확인하지 않습니다.")
            return
        }
        isChecking = true
        defer { isChecking = false }
        do {
            let updater = AppUpdater(source: GitHubReleaseSource(repository: Self.repository),
                                     bundleID: Bundle.main.bundleIdentifier ?? AppIdentity.bundleID, staging: Self.stagingFolder)
            let release: AppRelease
            do {
                release = try await updater.latest()
            } catch {
                record("확인하지 못했습니다: \(error.localizedDescription) 다음에 다시 확인합니다.")
                return
            }
            switch UpdateDecision.decide(release, currentVersion: Self.currentVersion, currentBuild: Self.currentBuild,
                                         failed: failedRelease, automatic: automatic) {
            case .upToDate:
                record("최신 버전입니다.")
            case .skipFailed:
                record("\(release.version) 은 받지 못했던 버전이라 자동으로 다시 받지 않습니다. 「지금 확인」 으로 다시 받을 수 있습니다.")
            case .download:
                record("\(release.version) 을 받는 중입니다.")
                do {
                    let app = try await updater.download(release)
                    failedRelease = nil
                    pending = (release, app)
                    installPendingIfFree()
                } catch {
                    fail(release, reason: "받지 못했습니다: \(error.localizedDescription)")
                }
            }
        }
    }

    private func installPendingIfFree() {
        guard let pending else { return }
        if isBusy() {
            record("\(pending.release.version) 이 준비됐습니다. 녹화가 끝나면 바꿉니다.")
            DispatchQueue.main.asyncAfter(deadline: .now() + 30) { [weak self] in self?.installPendingIfFree() }
            return
        }
        install(pending.app, release: pending.release)
    }

    /// Puts the verified app where this one is and relaunches. The running app's bundle can be
    /// moved aside while it runs; the old copy is removed once the new one has started.
    private func install(_ app: URL, release: AppRelease) {
        let target = Bundle.main.bundleURL
        let aside = target.deletingLastPathComponent()
            .appendingPathComponent(".\(target.deletingPathExtension().lastPathComponent)-\(Self.currentVersion).app")
        let fileManager = FileManager.default
        do {
            try? fileManager.removeItem(at: aside)
            try fileManager.moveItem(at: target, to: aside)
            do {
                try fileManager.moveItem(at: app, to: target)
            } catch {
                try? fileManager.moveItem(at: aside, to: target)
                throw error
            }
        } catch {
            pending = nil
            fail(release, reason: "\(release.version) 으로 바꾸지 못했습니다(\(target.deletingLastPathComponent().path) 에 쓸 수 없음).")
            return
        }
        pending = nil
        record("\(release.version) 으로 바꿨습니다. 다시 켭니다.")
        let script = """
            while kill -0 \(ProcessInfo.processInfo.processIdentifier) 2>/dev/null; do sleep 0.2; done
            open "$1"; rm -rf "$2"
            """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", script, "relaunch", target.path, aside.path]
        try? process.run()
        NSApp.terminate(nil)
    }

    /// The release that failed last, kept across launches.
    private var failedRelease: FailedRelease? {
        get { UserDefaults.standard.data(forKey: Self.failedReleaseKey).flatMap { try? JSONDecoder().decode(FailedRelease.self, from: $0) } }
        set { UserDefaults.standard.set(newValue.flatMap { try? JSONEncoder().encode($0) }, forKey: Self.failedReleaseKey) }
    }

    private func fail(_ release: AppRelease, reason: String) {
        failedRelease = FailedRelease(release)
        record("\(reason) 자동으로 다시 받지 않습니다.")
        Self.notifyFailure(version: release.version, reason: reason)
    }

    /// A notification, since the failure happens in the background. The permission is asked the first time.
    private static func notifyFailure(version: String, reason: String) {
        Task {
            let center = UNUserNotificationCenter.current()
            guard (try? await center.requestAuthorization(options: [.alert])) == true else { return }
            let content = UNMutableNotificationContent()
            content.title = "\(AppIdentity.name) \(version) 업데이트 실패"
            content.body = "\(reason) 자동으로 다시 받지 않으니, 설정 › 정보 › 업데이트의 「지금 확인」 으로 다시 받아 주세요."
            try? await center.add(UNNotificationRequest(identifier: "update.failed", content: content, trigger: nil))
        }
    }

    private func record(_ message: String) {
        let check = LastCheck(at: Date(), message: message)
        lastCheck = check
        if let data = try? JSONEncoder().encode(check) { UserDefaults.standard.set(data, forKey: Self.lastCheckKey) }
    }

    private static var stagingFolder: URL {
        SettingsStore.supportDirectory.appendingPathComponent("update", isDirectory: true)
    }
}
