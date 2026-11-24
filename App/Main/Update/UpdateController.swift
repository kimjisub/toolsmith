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

    /// `automatic` is the launch and six-hourly check; Check Now is not.
    func check(automatic: Bool = false) async {
        guard !isChecking else { return }
        guard canUpdate else {
            record(String(localized: "Development builds don’t check for updates."))
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
                record(String(localized: "Couldn’t check: \(error.localizedDescription) Will try again at the next check."))
                return
            }
            switch UpdateDecision.decide(release, currentVersion: Self.currentVersion, currentBuild: Self.currentBuild,
                                         failed: failedRelease, automatic: automatic) {
            case .upToDate:
                record(String(localized: "You’re up to date."))
            case .skipFailed:
                record(String(localized: "\(release.version) failed before, so it won’t be downloaded again automatically. Use Check Now to try again."))
            case .download:
                record(String(localized: "Downloading \(release.version)…"))
                do {
                    let app = try await updater.download(release)
                    failedRelease = nil
                    pending = (release, app)
                    installPendingIfFree()
                } catch {
                    fail(release, reason: String(localized: "Couldn’t download: \(error.localizedDescription)"))
                }
            }
        }
    }

    private func installPendingIfFree() {
        guard let pending else { return }
        if isBusy() {
            record(String(localized: "\(pending.release.version) is ready. It will be installed when the recording ends."))
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
            fail(release, reason: String(localized: "Couldn’t install \(release.version) (\(target.deletingLastPathComponent().path) isn’t writable)."))
            return
        }
        pending = nil
        record(String(localized: "Installed \(release.version). Reopening."))
        Relaunch.now(opening: target, removing: aside)
    }

    /// The release that failed last, kept across launches.
    private var failedRelease: FailedRelease? {
        get { UserDefaults.standard.data(forKey: Self.failedReleaseKey).flatMap { try? JSONDecoder().decode(FailedRelease.self, from: $0) } }
        set { UserDefaults.standard.set(newValue.flatMap { try? JSONEncoder().encode($0) }, forKey: Self.failedReleaseKey) }
    }

    private func fail(_ release: AppRelease, reason: String) {
        failedRelease = FailedRelease(release)
        record(String(localized: "\(reason) It won’t be downloaded again automatically."))
        Self.notifyFailure(version: release.version, reason: reason)
    }

    /// A notification, since the failure happens in the background. The permission is asked the first time.
    private static func notifyFailure(version: String, reason: String) {
        Task {
            let center = UNUserNotificationCenter.current()
            guard (try? await center.requestAuthorization(options: [.alert])) == true else { return }
            let content = UNMutableNotificationContent()
            content.title = String(localized: "\(AppIdentity.name) \(version) update failed")
            content.body = String(localized: "\(reason) It won’t be downloaded again automatically. To try again, use Check Now in Settings › About › Updates.")
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
