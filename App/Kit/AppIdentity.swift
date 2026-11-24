import Foundation

/// The app's name and identifiers, as project.yml sets them (the only place they are written).
/// They reach the code through this framework's Info.plist, so the app, its helper and the tests
/// all read the same values.
public enum AppIdentity {
    /// Shown everywhere the app names itself.
    public static let name = value("AppName")
    /// Accessibility grants, the login item, keychain items and the app-support folder are all
    /// tied to this. Changing it starts the app over for its users (see CLAUDE.md, 주의).
    public static let bundleID = value("AppBundleID")
    /// The Apple Developer team that signs released builds. The update check and the charge helper
    /// trust only code signed by this team.
    public static let teamID = value("AppTeamID")
    /// The GitHub repository whose releases the app updates itself from ("owner/name").
    public static let updateRepository = value("AppUpdateRepository")

    /// The charge helper's bundle id, launchd label and Mach service name.
    public static var helperBundleID: String { bundleID + ".helper" }
    /// The name without spaces, for HTTP User-Agent headers and file names.
    public static var compactName: String { name.replacingOccurrences(of: " ", with: "") }

    private final class Marker {}

    private static func value(_ key: String) -> String {
        guard let value = Bundle(for: Marker.self).object(forInfoDictionaryKey: key) as? String, !value.isEmpty, !value.hasPrefix("$(") else {
            preconditionFailure("\(key) is missing from the framework's Info.plist; it comes from project.yml")
        }
        return value
    }
}
