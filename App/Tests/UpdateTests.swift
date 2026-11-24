import XCTest
@testable import ToolsmithKit

final class UpdateTests: XCTestCase {
    func testNewerComparesVersionThenBuild() {
        let release = AppRelease(version: "2026.11.2", build: 40, sha256: "", size: 0, dmg: "")
        XCTAssertTrue(release.isNewer(than: "2026.11.1", build: 99))
        XCTAssertTrue(release.isNewer(than: "2026.11.2", build: 39))
        XCTAssertFalse(release.isNewer(than: "2026.11.2", build: 40))
        XCTAssertFalse(release.isNewer(than: "2026.12.0", build: 1))
        XCTAssertTrue(release.isNewer(than: "2026.9", build: 100))                        // 11 > 9, not "1" < "9"
    }

    func testAFailedReleaseIsNotFetchedAgainAutomatically() {
        let release = AppRelease(version: "2026.11.3", build: 41, sha256: "", size: 0, dmg: "")
        let failed = FailedRelease(release)
        func decide(failed: FailedRelease?, automatic: Bool) -> UpdateDecision {
            UpdateDecision.decide(release, currentVersion: "2026.11.2", currentBuild: 40, failed: failed, automatic: automatic)
        }
        XCTAssertEqual(decide(failed: nil, automatic: true), .download)
        XCTAssertEqual(decide(failed: failed, automatic: true), .skipFailed)
        XCTAssertEqual(decide(failed: failed, automatic: false), .download)       // 「지금 확인」 tries it again
        // A later release is fetched even though an earlier one failed.
        let older = FailedRelease(AppRelease(version: "2026.11.3", build: 40, sha256: "", size: 0, dmg: ""))
        XCTAssertEqual(decide(failed: older, automatic: true), .download)
        XCTAssertEqual(UpdateDecision.decide(release, currentVersion: "2026.11.3", currentBuild: 41, failed: nil, automatic: true), .upToDate)
    }

    func testReleaseManifest() throws {
        let json = #"{"version":"2026.11.1","build":12,"sha256":"ab","size":3,"dmg":"Toolsmith-2026.11.1.dmg"}"#
        XCTAssertEqual(try JSONDecoder().decode(AppRelease.self, from: Data(json.utf8)),
                       AppRelease(version: "2026.11.1", build: 12, sha256: "ab", size: 3, dmg: "Toolsmith-2026.11.1.dmg"))
    }

    func testGitHubLatestReleaseAssets() throws {
        let json = #"""
        {"tag_name":"v2026.11.1","assets":[
          {"name":"Toolsmith-2026.11.1.dmg","url":"https://api.github.com/repos/o/r/releases/assets/1","size":10},
          {"name":"release.json","url":"https://api.github.com/repos/o/r/releases/assets/2","size":1}]}
        """#
        let assets = try GitHubReleaseSource.assets(fromLatestRelease: Data(json.utf8))
        XCTAssertEqual(assets.map(\.name), ["Toolsmith-2026.11.1.dmg", "release.json"])
        XCTAssertEqual(assets[1].url.absoluteString, "https://api.github.com/repos/o/r/releases/assets/2")
    }

    func testChecksum() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file) }
        try Data("abc".utf8).write(to: file)
        XCTAssertEqual(try AppUpdater.sha256(of: file), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }

    func testPublicRepositoryIsReadWithoutAToken() {
        let url = URL(string: "https://api.github.com/repos/o/r/releases/latest")!
        XCTAssertNil(GitHubReleaseSource(repository: "o/r").request(url, accept: "application/json").value(forHTTPHeaderField: "Authorization"))
        XCTAssertEqual(GitHubReleaseSource(repository: "o/r", token: "t").request(url, accept: "application/json").value(forHTTPHeaderField: "Authorization"), "Bearer t")
    }
}
