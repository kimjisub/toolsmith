import Foundation
import XCTest
@testable import ToolsmithKit

final class ModuleTests: XCTestCase {
    private func module(_ id: String, default on: Bool = true, canDisable: Bool = true, requires: [String] = [],
                        permissions: [ModulePermission] = []) -> ModuleDescriptor {
        ModuleDescriptor(id: id, title: id, summary: "", symbol: "circle", tint: .gray, defaultEnabled: on,
                         canDisable: canDisable, requires: requires, permissions: permissions)
    }

    // MARK: Switches

    func testUntouchedModuleFollowsItsDefault() {
        let switches = ModuleSwitches()
        XCTAssertTrue(switches.isOn(module("a")))
        XCTAssertFalse(switches.isOn(module("b", default: false)))
    }

    func testChoiceOutlivesTheDefault() {
        var switches = ModuleSwitches()
        switches.set(module("a"), on: false)
        switches.set(module("b", default: false), on: true)
        XCTAssertFalse(switches.isOn(module("a")))
        XCTAssertTrue(switches.isOn(module("b", default: false)))
    }

    func testAlwaysOnModuleCannotBeSwitchedOff() {
        var switches = ModuleSwitches(["core": false])
        XCTAssertTrue(switches.isOn(module("core", canDisable: false)))
        switches.set(module("core", canDisable: false), on: false)
        XCTAssertTrue(switches.isOn(module("core", canDisable: false)))
    }

    func testSwitchesEncodeAsAPlainObject() throws {
        let data = try JSONEncoder().encode(ModuleSwitches(["clipboard": false]))
        XCTAssertEqual(String(decoding: data, as: UTF8.self), #"{"clipboard":false}"#)
        XCTAssertEqual(try JSONDecoder().decode(ModuleSwitches.self, from: data), ModuleSwitches(["clipboard": false]))
    }

    // MARK: Resolver

    func testRequirementOffStopsTheDependentChain() {
        let modules = [module("launcher"), module("ai", requires: ["launcher"]), module("deep", requires: ["ai"]), module("windows")]
        XCTAssertEqual(ModuleResolver.enabled(modules, switches: ModuleSwitches()), ["launcher", "ai", "deep", "windows"])
        XCTAssertEqual(ModuleResolver.enabled(modules, switches: ModuleSwitches(["launcher": false])), ["windows"])
    }

    func testUnknownRequirementKeepsTheModuleOff() {
        XCTAssertEqual(ModuleResolver.enabled([module("a", requires: ["missing"])], switches: ModuleSwitches()), [])
    }

    func testMissingRequirementsAreNamed() {
        let modules = [module("launcher"), module("ai", requires: ["launcher"])]
        let enabled = ModuleResolver.enabled(modules, switches: ModuleSwitches(["launcher": false]))
        XCTAssertEqual(ModuleResolver.missingRequirements(of: modules[1], in: modules, enabled: enabled).map(\.id), ["launcher"])
        XCTAssertEqual(ModuleResolver.missingRequirements(of: modules[1], in: modules, enabled: ["launcher", "ai"]), [])
    }

    func testPermissionsComeFromRunningModulesOnly() {
        let modules = [module("windows", permissions: [.accessibility]), module("capture", permissions: [.screenRecording, .microphone]),
                       module("clipboard", permissions: [.clipboard, .accessibility])]
        XCTAssertEqual(ModuleResolver.permissions(modules, enabled: ["capture", "clipboard"]), [.accessibility, .screenRecording, .clipboard, .microphone])
        XCTAssertEqual(ModuleResolver.permissions(modules, enabled: []), [])
    }

    // MARK: Settings migration

    func testSchemaOneScreenTimeOffBecomesTheModuleSwitch() throws {
        let settings = try JSONDecoder().decode(Settings.self, from: Data(#"{"schemaVersion":1,"screenTimeEnabled":false}"#.utf8))
        XCTAssertEqual(settings.modules.choices, ["screenTime": false])
        XCTAssertEqual(settings.schemaVersion, Settings.currentSchema)
    }

    func testSchemaOneScreenTimeOnLeavesEveryModuleUntouched() throws {
        let settings = try JSONDecoder().decode(Settings.self, from: Data(#"{"schemaVersion":1,"screenTimeEnabled":true}"#.utf8))
        XCTAssertEqual(settings.modules, ModuleSwitches())
    }

    func testSchemaOneMenuBarIsCarriedOver() throws {
        let json = #"{"schemaVersion":1,"menuBarMeters":["cpu","teleport","network"],"menuBarReadout":false}"#
        let layout = try JSONDecoder().decode(Settings.self, from: Data(json.utf8)).menuBarLayout
        let shown = layout.shown(MenuBarFixture.all).map { "\($0.id):\($0.style.rawValue)" }
        XCTAssertEqual(shown, ["monitor.cpu:graph", "monitor.network:graph"])
        XCTAssertTrue(layout.combined)
    }

    func testSchemaOneWithNothingChosenShowsTheAppIcon() throws {
        let json = #"{"menuBarMeters":[],"menuBarReadout":false}"#
        let layout = try JSONDecoder().decode(Settings.self, from: Data(json.utf8)).menuBarLayout
        XCTAssertEqual(layout.shown(MenuBarFixture.all).map(\.id), ["app.icon"])
    }

    func testSchemaTwoRoundTrips() throws {
        var settings = Settings()
        settings.modules.set(ModuleDescriptor(id: "clipboard", title: "", summary: "", symbol: "", tint: .green), on: false)
        settings.menuBarLayout.setVisible("clipboard.icon", true, among: MenuBarFixture.all)
        let again = try JSONDecoder().decode(Settings.self, from: JSONEncoder().encode(settings))
        XCTAssertEqual(again, settings)
        // The old keys are not written any more.
        let text = String(decoding: try JSONEncoder().encode(settings), as: UTF8.self)
        XCTAssertFalse(text.contains("menuBarMeters"))
        XCTAssertFalse(text.contains("screenTimeEnabled"))
    }

    func testNewInstallShowsWhatTheAppShowedBefore() {
        XCTAssertEqual(Settings().menuBarLayout.shown(MenuBarFixture.all).map(\.id),
                       ["monitor.cpu", "monitor.memory", "monitor.disk", "monitor.network", "monitor.battery", "monitor.readout"])
    }

    @MainActor func testLauncherModelWithoutAIOffersNoAIRow() {
        let engine = LauncherEngine(sources: [], usage: UsageLog(fileURL: tempFile()))
        let model = LauncherModel(engine: engine, usage: UsageLog(fileURL: tempFile()))
        model.query = "날씨"
        XCTAssertTrue(model.showsAIRow)
        model.allowsAI = false
        XCTAssertFalse(model.showsAIRow)
        model.query = ""
        model.query = ".hello"
        XCTAssertEqual(model.mode, .commands)
        XCTAssertEqual(model.query, ".hello")
    }

    @MainActor func testSwitchingAIOffLeavesAIMode() {
        let engine = LauncherEngine(sources: [], usage: UsageLog(fileURL: tempFile()))
        let model = LauncherModel(engine: engine, usage: UsageLog(fileURL: tempFile()))
        model.enterAIMode()
        model.allowsAI = false
        XCTAssertEqual(model.mode, .commands)
    }
}

enum MenuBarFixture {
    static func item(_ id: String, _ styles: [MenuBarStyle], visible: Bool) -> MenuBarItemDescriptor {
        MenuBarItemDescriptor(id: id, moduleID: String(id.split(separator: ".")[0]), title: id, symbol: "circle", styles: styles, defaultVisible: visible)
    }

    static let monitor: [MenuBarItemDescriptor] = ["cpu", "memory", "disk", "network", "battery"].map { item("monitor.\($0)", [.graph, .value, .iconAndValue], visible: true) }
        + [item("monitor.readout", [.value, .iconAndValue], visible: true)]
    static let clipboard = item("clipboard.icon", [.icon], visible: false)
    static let all: [MenuBarItemDescriptor] = [.appIcon] + [clipboard] + monitor
}
