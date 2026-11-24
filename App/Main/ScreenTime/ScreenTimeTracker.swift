import AppKit
import ToolsmithKit

/// Every few seconds, credits the app in front with that time, unless the user is away (no input
/// for a while and no call under way). The time is
/// collected in memory and written once a minute (and when the app quits), not on every tick.
@MainActor final class ScreenTimeTracker {
    static let interval: TimeInterval = 5
    static let flushInterval: TimeInterval = 60
    private let store: ScreenTimeStore
    private var timer: Timer?
    private var lastTick = Date()
    private var lastFlush = Date()
    private var lastPrunedDay: Int?
    /// Seconds per app and hour, not yet written.
    private var pending: [String: (seconds: Double, bundleID: String, name: String, date: Date)] = [:]
    init(store: ScreenTimeStore) { self.store = store }

    func start() {
        guard timer == nil else { return }
        lastTick = Date()
        let timer = Timer(timeInterval: Self.interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        timer.tolerance = 1
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// Writes what was collected and stops counting.
    func stop() {
        timer?.invalidate()
        timer = nil
        flush()
    }

    private func tick() {
        let now = Date()
        // Collected time belongs to the minute it was spent in; after a long gap, write it first.
        if now.timeIntervalSince(lastTick) >= Self.interval * 3, !pending.isEmpty { flush() }
        let elapsed = now.timeIntervalSince(lastTick)
        lastTick = now
        // A long gap means the Mac slept (or the app was stalled): that time was not spent at the screen.
        guard elapsed > 0, elapsed < Self.interval * 3 else { return }
        guard ActivityRule.shouldCount(idleSeconds: Self.idleSeconds, screenLocked: Self.isScreenLocked,
                                       displayAsleep: CGDisplayIsAsleep(CGMainDisplayID()) != 0,
                                       inCall: CallActivity.isActive, enabled: true),
              let app = NSWorkspace.shared.frontmostApplication, let bundleID = app.bundleIdentifier else { return }
        let key = "\(bundleID)|\(Calendar.current.component(.hour, from: now))|\(Calendar.current.component(.day, from: now))"
        var entry = pending[key] ?? (0, bundleID, app.localizedName ?? bundleID, now)
        entry.seconds += elapsed
        pending[key] = entry
        if now.timeIntervalSince(lastFlush) >= Self.flushInterval { flush() }
    }

    /// Writes the collected time, and once a day drops what is older than the retention.
    func flush() {
        let now = Date()
        lastFlush = now
        store.add(Array(pending.values))
        pending = [:]
        let day = Calendar.current.ordinality(of: .day, in: .era, for: now)
        if day != lastPrunedDay {
            lastPrunedDay = day
            store.prune(now: now)
        }
    }

    /// Seconds since the last key press, click or pointer movement.
    private static var idleSeconds: Double {
        let kinds: [CGEventType] = [.keyDown, .mouseMoved, .leftMouseDown, .rightMouseDown, .scrollWheel, .leftMouseDragged]
        return kinds.map { CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: $0) }.min() ?? 0
    }

    private static var isScreenLocked: Bool {
        guard let session = CGSessionCopyCurrentDictionary() as? [String: Any] else { return false }
        return session["CGSSessionScreenIsLocked"] as? Bool == true
    }
}
