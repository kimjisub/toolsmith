import Foundation

public struct AppEntry: Equatable {
    public let url: URL
    /// The name as Finder shows it in the user's language ("메모").
    public let name: String
    /// Other names the app is known by ("Notes"), so it is found in either language.
    public let alternateNames: [String]

    public init(url: URL, name: String, alternateNames: [String]) {
        self.url = url
        self.name = name
        self.alternateNames = alternateNames
    }
}

/// Finds the apps installed on this Mac.
public enum AppCatalog {
    public static var defaultDirectories: [URL] {
        [
            URL(fileURLWithPath: "/Applications"),
            URL(fileURLWithPath: "/System/Applications"),
            URL(fileURLWithPath: "/System/Applications/Utilities"),
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications"),
            URL(fileURLWithPath: "/System/Library/CoreServices/Applications"),
            // Safari ships in a cryptex; /Applications/Safari.app is a hidden symlink that listings skip.
            URL(fileURLWithPath: "/System/Cryptexes/App/System/Applications"),
        ]
    }

    /// Apps directly inside each directory and inside its immediate subfolders (Utilities, a vendor
    /// folder). Never looks inside an app bundle. Sorted by name; the same path is listed once.
    public static func scan(_ directories: [URL], localizedName: (URL) -> String) -> [AppEntry] {
        var seen: Set<String> = []
        var entries: [AppEntry] = []

        func add(_ url: URL) {
            let path = url.standardizedFileURL.path
            guard seen.insert(path).inserted else { return }
            entries.append(entry(for: url, localizedName: localizedName))
        }

        for directory in directories {
            for item in children(of: directory) {
                if isApp(item) {
                    add(item)
                } else if isDirectory(item) {
                    children(of: item).filter(isApp).forEach(add)
                }
            }
        }
        return entries.sorted {
            let order = $0.name.localizedCaseInsensitiveCompare($1.name)
            return order == .orderedSame ? $0.url.path < $1.url.path : order == .orderedAscending
        }
    }

    private static func entry(for url: URL, localizedName: (URL) -> String) -> AppEntry {
        let fileName = url.deletingPathExtension().lastPathComponent
        var name = localizedName(url)
        if name.lowercased().hasSuffix(".app") { name = String(name.dropLast(4)) }
        if name.isEmpty { name = fileName }

        let info = NSDictionary(contentsOf: url.appendingPathComponent("Contents/Info.plist")) as? [String: Any] ?? [:]
        var alternates: [String] = []
        for candidate in [fileName, info["CFBundleDisplayName"] as? String, info["CFBundleName"] as? String] {
            guard let candidate, !candidate.isEmpty, candidate != name, !alternates.contains(candidate) else { continue }
            alternates.append(candidate)
        }
        return AppEntry(url: url, name: name, alternateNames: alternates)
    }

    private static func children(of directory: URL) -> [URL] {
        (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isDirectoryKey],
                                                      options: [.skipsHiddenFiles])) ?? []
    }

    private static func isApp(_ url: URL) -> Bool { url.pathExtension.lowercased() == "app" }

    private static func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
    }
}
