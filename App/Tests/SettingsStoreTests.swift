import XCTest
@testable import ToolsmithKit

final class SettingsStoreTests: XCTestCase {
    func testDefaultsWhenMissing() { XCTAssertEqual(SettingsStore(fileURL: tempFile()).settings, Settings()) }

    func testUpdatePersists() {
        let url = tempFile(); let store = SettingsStore(fileURL: url)
        store.update { $0.launchAtLogin = false }
        XCTAssertFalse(SettingsStore(fileURL: url).settings.launchAtLogin)
    }

    func testHotkeysPersist() {
        let url = tempFile(); let store = SettingsStore(fileURL: url)
        let combo = KeyCombo(keyCode: 43, modifiers: [.option])
        store.update { _ = $0.hotkeys.assign(combo, to: "util.settings") }
        XCTAssertEqual(SettingsStore(fileURL: url).settings.hotkeys.combo(for: "util.settings"), combo)
    }

    func testCorruptStoreFallsBackToDefaults() throws {
        let url = tempFile(); try Data("{".utf8).write(to: url)
        XCTAssertEqual(SettingsStore(fileURL: url).settings, Settings())
        // The damaged file is kept aside, not destroyed.
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path + ".broken"))
    }

    func testUnknownFieldsAndMissingFieldsAreTolerated() throws {
        let url = tempFile(); try Data(#"{"schemaVersion":1,"future":true}"#.utf8).write(to: url)
        let settings = SettingsStore(fileURL: url).settings
        XCTAssertEqual(settings.hotkeys, .defaults); XCTAssertTrue(settings.launchAtLogin)
    }

    func testUpdateHotkeysSavesNothingWhenItThrows() {
        let url = tempFile(); let store = SettingsStore(fileURL: url)
        XCTAssertThrowsError(try store.updateHotkeys { try $0.clear(HotkeyID.openLauncher) })
        XCTAssertEqual(store.settings.hotkeys, .defaults)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    func testLoginItemDefaultIsAppliedOnlyOnce() throws {
        let url = tempFile(); let store = SettingsStore(fileURL: url)
        XCTAssertFalse(store.settings.loginItemInitialized)
        store.update { $0.loginItemInitialized = true }
        XCTAssertTrue(SettingsStore(fileURL: url).settings.loginItemInitialized)
        // A file written before this field existed counts as not yet applied.
        let old = tempFile(); try Data(#"{"schemaVersion":1,"launchAtLogin":true}"#.utf8).write(to: old)
        XCTAssertFalse(SettingsStore(fileURL: old).settings.loginItemInitialized)
    }

    func testWindowSettingsDefaultsAndPersistence() throws {
        let old = tempFile(); try Data(#"{"schemaVersion":1}"#.utf8).write(to: old)
        let store = SettingsStore(fileURL: old)
        XCTAssertEqual(store.settings.windowGap, 0); XCTAssertEqual(store.settings.seededHotkeys, [])
        store.update { $0.windowGap = 8; $0.seededHotkeys = ["window.left-half"] }
        let again = SettingsStore(fileURL: old).settings
        XCTAssertEqual(again.windowGap, 8); XCTAssertEqual(again.seededHotkeys, ["window.left-half"])
    }

    func testNewInstallKeepsClipboardHistoryForever() {
        XCTAssertEqual(Settings().clipRetention, .forever)
        XCTAssertNil(Settings().clipRetention.cutoff(now: Date()))
    }

    func testClipboardSettingsDefaults() throws {
        let old = tempFile(); try Data(#"{"schemaVersion":1}"#.utf8).write(to: old)
        let settings = SettingsStore(fileURL: old).settings
        XCTAssertEqual(settings.clipRetention, .forever)
        XCTAssertFalse(settings.clipboardPaused)
        XCTAssertEqual(settings.clipIgnoredApps, ClipboardPolicy.defaultIgnoredApps)
    }

    func testAIModelDefault() throws {
        let old = tempFile(); try Data(#"{"schemaVersion":1}"#.utf8).write(to: old)
        XCTAssertEqual(SettingsStore(fileURL: old).settings.aiModel, AIRequest.defaultModel)
        XCTAssertEqual(AIRequest.defaultModel, "anthropic/claude-haiku-5.5")
    }

    func testCaptureSettingsDefaults() throws {
        let old = tempFile(); try Data(#"{"schemaVersion":1}"#.utf8).write(to: old)
        let settings = SettingsStore(fileURL: old).settings
        XCTAssertNil(settings.captureFolder); XCTAssertTrue(settings.captureCopiesToClipboard); XCTAssertEqual(settings.colorFormat, .hex)
    }

    func testRecordingSettingsDefaultToSilent() throws {
        let old = tempFile(); try Data(#"{"schemaVersion":1}"#.utf8).write(to: old)
        let settings = SettingsStore(fileURL: old).settings
        XCTAssertFalse(settings.recordSystemAudio); XCTAssertFalse(settings.recordMicrophone)
    }


    func testScreenTimeIsOnByDefault() throws {
        let old = tempFile(); try Data(#"{"schemaVersion":1}"#.utf8).write(to: old)
        XCTAssertNil(SettingsStore(fileURL: old).settings.modules.choices["screenTime"])
    }

    func testDefaultURLIsUnderOurBundleID() {
        XCTAssertTrue(SettingsStore.defaultURL.path.hasSuffix("Application Support/\(AppIdentity.bundleID)/settings.json"))
    }
}
