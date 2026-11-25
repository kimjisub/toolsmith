import Foundation
import ToolsmithKit

/// Writes macOS's own charge limit as PowerUIAgent's preferences (see `NativeChargeLimit`). Root only:
/// the agent reads root's preferences. Keeps the agent's values from before the first write so
/// giving back puts the user's own setting back.
final class NativeLimitWriter {
    private let client: SystemChargeLimitClient
    private let originalsFile: URL
    private var domain: CFString { NativeChargeLimit.domain as CFString }

    init?(folder: URL) {
        guard let client = SystemChargeLimitClient() else { return nil }
        self.client = client
        originalsFile = folder.appendingPathComponent("native-limit-originals.json")
    }

    /// What macOS enforces now: the target in percent, or nil while its limit is off.
    func reported() -> Int? {
        guard let state = client.read(), state.mode == .on else { return nil }
        return state.limit
    }

    /// Sets the target and asks the agent to reload. False when the preferences could not be saved.
    func write(_ percent: Int) -> Bool {
        saveOriginalsOnce()
        return set(featureState: 1, limit: percent) && postReload()
    }

    /// Puts back the agent's values from before the helper, or switches the limit off when it was off.
    func giveBack() -> String? {
        guard let data = try? Data(contentsOf: originalsFile),
              let originals = try? JSONDecoder().decode(NativeChargeLimit.Originals.self, from: data) else { return nil }
        let failure: String?
        if originals.featureState == 1, let limit = originals.limit {
            failure = set(featureState: 1, limit: limit) && postReload() ? nil : "Couldn’t put back macOS’s charge limit"
        } else {
            failure = client.disable()
        }
        if failure == nil { try? FileManager.default.removeItem(at: originalsFile) }
        return failure
    }

    private func saveOriginalsOnce() {
        guard !FileManager.default.fileExists(atPath: originalsFile.path) else { return }
        let originals = NativeChargeLimit.Originals(featureState: preference(NativeChargeLimit.featureStateKey),
                                                    limit: preference(NativeChargeLimit.limitKey))
        guard let data = try? JSONEncoder().encode(originals) else { return }
        try? data.write(to: originalsFile, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: originalsFile.path)
    }

    private func preference(_ key: String) -> Int? {
        (CFPreferencesCopyValue(key as CFString, domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost) as? NSNumber)?.intValue
    }

    private func set(featureState: Int, limit: Int) -> Bool {
        CFPreferencesSetValue(NativeChargeLimit.featureStateKey as CFString, NSNumber(value: featureState), domain,
                              kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        CFPreferencesSetValue(NativeChargeLimit.limitKey as CFString, NSNumber(value: limit), domain,
                              kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        return CFPreferencesSynchronize(domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
    }

    /// `notify_post`, looked up at run time: the notify API has no Swift module of its own.
    private func postReload() -> Bool {
        typealias NotifyPost = @convention(c) (UnsafePointer<CChar>) -> UInt32
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "notify_post") else { return false }
        return unsafeBitCast(symbol, to: NotifyPost.self)(NativeChargeLimit.reloadNotification) == 0
    }
}
