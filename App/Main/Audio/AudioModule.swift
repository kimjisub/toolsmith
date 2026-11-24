import AppKit
import Combine
import SwiftUI
import ToolsmithKit

/// Sound: the Mac's output, input and alert devices, and every app's own volume, boost, output
/// and effects, as a screen of the menu bar panel. Switched off, every route is taken down, so each
/// app plays as macOS plays it.
@MainActor final class AudioModule: AppModule {
    nonisolated static let screenID = "audio"
    nonisolated static let volumeItemID = "audio.volume"
    nonisolated static let descriptor = ModuleDescriptor(
        id: screenID, title: String(localized: "Sound"), summary: String(localized: "Change the output, input and alert devices, and each app's volume, output and effects"),
        symbol: "speaker.wave.2.fill", tint: .pink, permissions: [.audioCapture],
        menuBarItems: [MenuBarItemDescriptor(id: volumeItemID, moduleID: screenID, title: String(localized: "Output volume"), symbol: "speaker.wave.2.fill",
                                             styles: [.icon, .iconAndValue], defaultStyle: .icon, defaultVisible: true)])
    var descriptor: ModuleDescriptor { Self.descriptor }

    private unowned let host: ModuleHost
    let mixer: AudioMixer
    private let commands: AudioCommandSource
    private let viewState = MixerViewState()
    /// The app whose row opens with the screen, once (a development aid sets it).
    private var pendingExpanded: String?

    init(host: ModuleHost) {
        self.host = host
        mixer = AudioMixer(store: AudioConfigStore(fileURL: SettingsStore.supportDirectory
            .appendingPathComponent("audio", isDirectory: true).appendingPathComponent("audio.json")))
        commands = AudioCommandSource(mixer: mixer)
        commands.openMixer = { [weak self] in self?.open() }
        mixer.onCommandsChange = { [weak host] in host?.commandsChanged() }
    }

    var commandSources: [CommandSource] { [commands] }

    var appMenuItems: [AppMenuEntry] {
        [AppMenuEntry(title: String(localized: "Sound"), symbol: "speaker.wave.2") { [weak self] in self?.open() }]
    }

    var panelScreens: [PanelScreen] {
        [PanelScreen(id: Self.screenID, title: String(localized: "Sound"), symbol: Self.descriptor.symbol, width: MixerStyle.width,
                     settings: .module(Self.screenID),
                     content: { [weak self] in
                         guard let self else { return AnyView(EmptyView()) }
                         defer { self.pendingExpanded = nil }
                         return AnyView(MixerView(mixer: self.mixer, state: self.viewState, expandedApp: self.pendingExpanded))
                     },
                     // Levels and "playing" are read, and the meters' taps run, only while the screen is up.
                     onShow: { [weak self] _ in self?.mixer.setVisible(true) },
                     onHide: { [weak self] in self?.mixer.setVisible(false) },
                     // The equalizer's bands open in a popover: a click there must not close the panel.
                     auxiliaryWindows: { NSApp.windows.filter { $0.isVisible && $0.className.contains("Popover") } })]
    }

    var menuBarItems: [MenuBarItem] {
        let changes = mixer.$output.map { _ in () }.eraseToAnyPublisher()
        let descriptor = Self.descriptor.menuBarItems[0]
        return [MenuBarItem(descriptor: descriptor, glyph: { [mixer] style in Self.glyph(mixer.output, style: style) }, changes: changes,
                            click: { [weak host] frame in host?.openPanel(Self.screenID, below: frame) })]
    }

    /// A speaker that shows the output's level (and a slash when muted); with the value, the percentage.
    private static func glyph(_ output: SystemDeviceState, style: MenuBarStyle) -> MenuBarGlyph {
        let muted = output.muted ?? false
        let volume = output.volume ?? 0
        let symbol = muted ? "speaker.slash.fill" : volume < 0.01 ? "speaker.fill" : volume < 0.34 ? "speaker.wave.1.fill"
            : volume < 0.67 ? "speaker.wave.2.fill" : "speaker.wave.3.fill"
        let percent = AudioGain.percentText(volume)
        let spoken = muted ? String(localized: "Output muted") : String(localized: "Output volume \(percent)")
        guard style == .iconAndValue, output.volume != nil else { return MenuBarGlyph(pieces: [.symbol(symbol)], spoken: spoken) }
        return MenuBarGlyph(pieces: [.symbol(symbol), .text(muted ? String(localized: "Off") : percent)], spoken: spoken)
    }

    func settingsGroups(in environment: AppEnvironment) -> AnyView? {
        AnyView(AudioSettingsGroups(mixer: mixer, open: { [weak self] in self?.open() }))
    }

    func start() { mixer.start() }

    func stop() {
        host.closePanel()
        mixer.stopAll()
    }

    /// The sound screen of the menu bar panel, under the app's menu bar item.
    func open() {
        host.openPanel(Self.screenID, below: host.menuBarAnchor())
    }

    #if TOOLSMITH_DEV
    func runDevelopmentAid(_ arguments: [String]) {
        if let index = arguments.firstIndex(of: "--expand"), index + 1 < arguments.count { pendingExpanded = arguments[index + 1] }
        if arguments.contains("--show-mixer") { DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in self?.open() } }
        AudioDevelopmentAids.run(arguments)
    }
    #endif
}
