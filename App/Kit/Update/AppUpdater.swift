import CryptoKit
import Foundation

/// A published build: what release.json beside the DMG says (written by scripts/publish-release.sh).
public struct AppRelease: Decodable, Equatable, Sendable {
    public let version: String
    public let build: Int
    public let sha256: String
    public let size: Int
    /// The DMG's file name among the release's files.
    public let dmg: String

    public init(version: String, build: Int, sha256: String, size: Int, dmg: String) {
        self.version = version
        self.build = build
        self.sha256 = sha256
        self.size = size
        self.dmg = dmg
    }

    /// Whether this release comes after the given version and build: dotted numbers compared
    /// part by part, then the build number.
    public func isNewer(than version: String, build: Int) -> Bool {
        let mine = Self.parts(self.version), theirs = Self.parts(version)
        for index in 0..<max(mine.count, theirs.count) {
            let left = index < mine.count ? mine[index] : 0
            let right = index < theirs.count ? theirs[index] : 0
            if left != right { return left > right }
        }
        return self.build > build
    }

    private static func parts(_ version: String) -> [Int] {
        version.split(separator: ".").map { Int($0) ?? 0 }
    }
}

/// A release whose download or install failed. Automatic checks leave it alone, so a broken
/// release is not fetched again every six hours; checking by hand still tries it.
public struct FailedRelease: Codable, Equatable, Sendable {
    public let version: String
    public let build: Int

    public init(_ release: AppRelease) {
        version = release.version
        build = release.build
    }

    public func matches(_ release: AppRelease) -> Bool { version == release.version && build == release.build }
}

/// What a check does with the newest release it found.
public enum UpdateDecision: Equatable, Sendable {
    case upToDate
    /// The automatic check found the release that failed before and does not fetch it again.
    case skipFailed
    case download

    public static func decide(_ release: AppRelease, currentVersion: String, currentBuild: Int,
                              failed: FailedRelease?, automatic: Bool) -> UpdateDecision {
        guard release.isNewer(than: currentVersion, build: currentBuild) else { return .upToDate }
        if automatic, failed?.matches(release) == true { return .skipFailed }
        return .download
    }
}

public enum AppUpdateError: LocalizedError, Equatable {
    case noRelease
    case server(Int)
    case checksumMismatch
    case notSigned(String)
    case missingApp
    case toolFailed(String)

    public var errorDescription: String? {
        switch self {
        case .noRelease: return localized("No release has been published.")
        case .server(let status): return localized("The update server did not respond (\(status)).")
        case .checksumMismatch: return localized("The downloaded file does not match the one in the release.")
        case .notSigned(let detail): return localized("Could not verify the downloaded app's signature: \(detail)")
        case .missingApp: return localized("The downloaded file contains no app.")
        case .toolFailed(let tool): return localized("Could not check the downloaded file (\(tool)).")
        }
    }
}

/// Where builds are published. The app only knows this shape, so the source can change.
public protocol ReleaseSource: Sendable {
    /// The newest release, and a way to fetch its DMG.
    func latest() async throws -> AppRelease
    /// Downloads the release's DMG to a temporary file.
    func downloadDMG(of release: AppRelease) async throws -> URL
}

/// Releases of one GitHub repository, read through the REST API. A public repository needs no
/// token; a fork that publishes from a private repository passes one that may read its contents.
public struct GitHubReleaseSource: ReleaseSource {
    public let repository: String
    let token: String?
    let session: URLSession

    public init(repository: String, token: String? = nil, session: URLSession = .shared) {
        self.repository = repository
        self.token = token
        self.session = session
    }

    public struct Asset: Decodable, Equatable, Sendable {
        public let name: String
        /// The API address of the file (downloaded with `Accept: application/octet-stream`).
        public let url: URL
    }

    struct Release: Decodable {
        let assets: [Asset]
    }

    /// The latest release's files, from the API's JSON.
    public static func assets(fromLatestRelease data: Data) throws -> [Asset] {
        try JSONDecoder().decode(Release.self, from: data).assets
    }

    public func latest() async throws -> AppRelease {
        guard let url = URL(string: "https://api.github.com/repos/\(repository)/releases/latest") else { throw AppUpdateError.noRelease }
        let (data, response) = try await session.data(for: request(url, accept: "application/vnd.github+json"))
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 404 { throw AppUpdateError.noRelease }
        guard status == 200 else { throw AppUpdateError.server(status) }
        let assets = try Self.assets(fromLatestRelease: data)
        guard let manifest = assets.first(where: { $0.name == "release.json" }) else { throw AppUpdateError.noRelease }
        let (body, manifestResponse) = try await session.data(for: request(manifest.url, accept: "application/octet-stream"))
        guard (manifestResponse as? HTTPURLResponse)?.statusCode == 200 else { throw AppUpdateError.server((manifestResponse as? HTTPURLResponse)?.statusCode ?? 0) }
        return try JSONDecoder().decode(AppRelease.self, from: body)
    }

    public func downloadDMG(of release: AppRelease) async throws -> URL {
        guard let latest = URL(string: "https://api.github.com/repos/\(repository)/releases/latest") else { throw AppUpdateError.noRelease }
        let (data, _) = try await session.data(for: request(latest, accept: "application/vnd.github+json"))
        guard let asset = try Self.assets(fromLatestRelease: data).first(where: { $0.name == release.dmg }) else { throw AppUpdateError.missingApp }
        let (file, response) = try await session.download(for: request(asset.url, accept: "application/octet-stream"))
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw AppUpdateError.server((response as? HTTPURLResponse)?.statusCode ?? 0) }
        let kept = FileManager.default.temporaryDirectory.appendingPathComponent("\(AppIdentity.compactName)-update-\(UUID().uuidString).dmg")
        try FileManager.default.moveItem(at: file, to: kept)
        return kept
    }

    func request(_ url: URL, accept: String) -> URLRequest {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 60)
        request.setValue(accept, forHTTPHeaderField: "Accept")
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue(AppIdentity.compactName, forHTTPHeaderField: "User-Agent")
        return request
    }
}

/// Finds, downloads and checks a newer build. Installing it (swapping the app and relaunching)
/// is the app's job; this only hands back a verified copy.
public struct AppUpdater: Sendable {
    /// Only builds signed with this Developer ID team are installed.
    public static let teamID = AppIdentity.teamID
    let source: ReleaseSource
    let bundleID: String
    let staging: URL

    public init(source: ReleaseSource, bundleID: String, staging: URL) {
        self.source = source
        self.bundleID = bundleID
        self.staging = staging
    }

    public func latest() async throws -> AppRelease { try await source.latest() }

    /// Downloads the release's DMG and returns its app, copied out of the DMG into `staging`,
    /// after the file matches the release's checksum and the app passes signature and
    /// notarization checks.
    public func download(_ release: AppRelease) async throws -> URL {
        let dmg = try await source.downloadDMG(of: release)
        defer { try? FileManager.default.removeItem(at: dmg) }
        guard try Self.sha256(of: dmg) == release.sha256.lowercased() else { throw AppUpdateError.checksumMismatch }
        return try Self.extractVerifiedApp(from: dmg, bundleID: bundleID, release: release, into: staging)
    }

    static func sha256(of file: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// Mounts the DMG read-only, checks the app inside, and copies it to `staging`.
    static func extractVerifiedApp(from dmg: URL, bundleID: String, release: AppRelease? = nil, into staging: URL) throws -> URL {
        let mount = FileManager.default.temporaryDirectory.appendingPathComponent("\(AppIdentity.compactName)-update-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: mount, withIntermediateDirectories: true)
        try run("/usr/bin/hdiutil", ["attach", "-nobrowse", "-readonly", "-noautoopen", "-quiet", "-mountpoint", mount.path, dmg.path])
        defer {
            _ = try? run("/usr/bin/hdiutil", ["detach", "-quiet", "-force", mount.path])
            try? FileManager.default.removeItem(at: mount)
        }
        let apps = (try? FileManager.default.contentsOfDirectory(at: mount, includingPropertiesForKeys: nil)) ?? []
        guard let app = apps.first(where: { $0.pathExtension == "app" && Bundle(url: $0)?.bundleIdentifier == bundleID }) else { throw AppUpdateError.missingApp }
        try verifySignature(of: app)
        // The app must be the build the release announced, not an older one under a newer label.
        if let release, let info = Bundle(url: app)?.infoDictionary {
            guard info["CFBundleShortVersionString"] as? String == release.version,
                  (info["CFBundleVersion"] as? String).flatMap(Int.init) == release.build else { throw AppUpdateError.checksumMismatch }
        }
        try? FileManager.default.removeItem(at: staging)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        let copy = staging.appendingPathComponent(app.lastPathComponent)
        try run("/usr/bin/ditto", [app.path, copy.path])
        return copy
    }

    /// The signature seals every file, it is this team's Developer ID, and Apple notarized it.
    static func verifySignature(of app: URL) throws {
        do {
            try run("/usr/bin/codesign", ["--verify", "--deep", "--strict", app.path])
        } catch {
            throw AppUpdateError.notSigned(localized("The signature is damaged"))
        }
        // codesign checks the requirement itself; its printed details include the app's path, which
        // the app's own folder name could forge.
        let requirement = "=anchor apple generic and certificate leaf[subject.OU] = \"\(teamID)\""
            + " and certificate 1[field.1.2.840.113635.100.6.2.6] exists and certificate leaf[field.1.2.840.113635.100.6.1.13] exists"
        do {
            try run("/usr/bin/codesign", ["--verify", "--deep", "--strict", "-R", requirement, app.path])
        } catch {
            throw AppUpdateError.notSigned(localized("It is not signed with the Developer ID of this app's developer"))
        }
        do {
            try run("/usr/sbin/spctl", ["--assess", "--type", "execute", app.path])
        } catch {
            throw AppUpdateError.notSigned(localized("It did not pass Apple's notarization"))
        }
    }

    /// Runs a tool and returns what it wrote (stdout and stderr together); a non-zero exit throws.
    @discardableResult
    static func run(_ tool: String, _ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw AppUpdateError.toolFailed("\(URL(fileURLWithPath: tool).lastPathComponent) \(process.terminationStatus)")
        }
        return String(decoding: data, as: UTF8.self)
    }
}
