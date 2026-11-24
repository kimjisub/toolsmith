import Foundation
import ToolsmithKit

/// The app's own language, kept where macOS reads it at launch: the `AppleLanguages` preference of
/// the app's domain, the same one System Settings → General → Language & Region → Applications
/// writes. Not in the settings file, because macOS picks the language before the app runs.
enum AppLanguagePreference {
    private static let key = "AppleLanguages"

    /// The choice the running app was launched with.
    static let launched = current

    static var current: AppLanguage {
        AppLanguage(preferredLanguages: UserDefaults.standard.persistentDomain(forName: AppIdentity.bundleID)?[key] as? [String])
    }

    static func set(_ language: AppLanguage) {
        _ = launched
        if let languages = language.preferredLanguages {
            UserDefaults.standard.set(languages, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }
}
