import AppKit
import SwiftUI
import ToolsmithKit

/// A page of the settings window. The pages of the app's shell are fixed; every running module
/// with a page of its own adds `.module(id)`.
enum SettingsPane: Hashable, Identifiable {
    case general, features, menuBar, hotkeys, permissions, privacy, about
    case module(String)

    // The modules' pages, by the names the rest of the app opens them with.
    static let clipboard = SettingsPane.module(ClipboardModule.descriptor.id)
    static let snippets = SettingsPane.module(SnippetsModule.descriptor.id)
    static let windows = SettingsPane.module(WindowsModule.descriptor.id)
    static let capture = SettingsPane.module(CaptureModule.descriptor.id)
    static let ai = SettingsPane.module(AIModule.descriptor.id)
    static let monitor = SettingsPane.module(MonitorModule.descriptor.id)
    static let battery = SettingsPane.module(ChargeModule.descriptor.id)
    static let screenTime = SettingsPane.module(ScreenTimeModule.descriptor.id)

    private static let fixed: [SettingsPane] = [.general, .features, .menuBar, .hotkeys, .permissions, .privacy, .about]

    var id: String { rawValue }

    /// Stable names, for the last page looked at and the development flags. A module's page is its id.
    var rawValue: String {
        switch self {
        case .general: return "general"
        case .features: return "features"
        case .menuBar: return "menuBar"
        case .hotkeys: return "hotkeys"
        case .permissions: return "permissions"
        case .privacy: return "privacy"
        case .about: return "about"
        case .module(let id): return id
        }
    }

    init(rawValue: String) {
        self = Self.fixed.first { $0.rawValue == rawValue } ?? .module(rawValue)
    }

    /// Every page a sidebar would show for these modules, in sidebar order.
    @MainActor static func all(_ modules: ModuleManager) -> [SettingsPane] {
        groups(modules).flatMap(\.1) + [.about]
    }

    /// The sidebar's groups; each is (title, panes). `about` sits apart at the bottom.
    @MainActor static func groups(_ modules: ModuleManager) -> [(String?, [SettingsPane])] {
        let pages = modules.running.map { SettingsPane.module($0.descriptor.id) }
        return [
            (nil, [.general, .features, .menuBar, .hotkeys]),
            ("기능", pages),
            ("앱", [.permissions, .privacy]),
        ].filter { !$0.1.isEmpty }
    }

    @MainActor func title(_ modules: ModuleManager) -> String {
        switch self {
        case .general: return "일반"
        case .features: return "기능"
        case .menuBar: return "메뉴 막대"
        case .hotkeys: return "단축키"
        case .permissions: return "권한"
        case .privacy: return "개인정보와 저장 공간"
        case .about: return "정보"
        case .module(let id): return modules.module(id: id)?.descriptor.title ?? id
        }
    }

    @MainActor func symbol(_ modules: ModuleManager) -> String {
        switch self {
        case .general: return "gearshape.fill"
        case .features: return "puzzlepiece.extension.fill"
        case .menuBar: return "menubar.rectangle"
        case .hotkeys: return "command"
        case .permissions: return "hand.raised.fill"
        case .privacy: return "lock.fill"
        case .about: return "info"
        case .module(let id): return modules.module(id: id)?.descriptor.symbol ?? "questionmark"
        }
    }

    @MainActor func color(_ modules: ModuleManager) -> Color {
        switch self {
        case .general, .about: return Tile.gray
        case .features: return Tile.blue
        case .menuBar: return Tile.indigo
        case .hotkeys: return Tile.gray
        case .permissions: return Tile.teal
        case .privacy: return Tile.teal
        case .module(let id): return modules.module(id: id)?.descriptor.tint.color ?? Tile.gray
        }
    }
}

/// The settings window: an ordinary window (it activates the app), drawn on the same dark glass.
/// It reopens on the section last looked at.
@MainActor final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    static let size = NSSize(width: 860, height: 600)
    private let environment: AppEnvironment

    init(environment: AppEnvironment) {
        self.environment = environment
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: Self.size),
                              styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.isOpaque = false
        window.backgroundColor = .clear
        window.appearance = NSAppearance(named: .darkAqua)
        window.isReleasedWhenClosed = false
        window.standardWindowButton(.miniaturizeButton)?.isEnabled = false
        window.standardWindowButton(.zoomButton)?.isEnabled = false
        super.init(window: window)
        window.delegate = self
        let host = NSHostingView(rootView: SettingsView(environment: environment, modules: environment.modules))
        host.sizingOptions = []
        window.contentView = host
        window.setContentSize(Self.size)
        window.center()
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("not used") }

    func show(_ pane: SettingsPane? = nil) {
        if let pane { environment.settingsPane = pane }
        environment.refreshSystemShortcuts()
        window?.title = "\(environment.settingsPane.title(environment.modules)) – \(AppIdentity.name)"
        // Open where the user is looking: on the display the pointer is on, unless it is already up.
        if let window, !window.isVisible {
            let pointer = NSEvent.mouseLocation
            if let screen = NSScreen.screens.first(where: { $0.frame.contains(pointer) }) ?? NSScreen.main {
                let visible = screen.visibleFrame
                window.setFrameOrigin(NSPoint(x: (visible.midX - window.frame.width / 2).rounded(),
                                              y: (visible.midY - window.frame.height / 2 + visible.height * 0.06).rounded()))
            }
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
        // Bring it above whatever is in front even when the system declines to activate us.
        window?.orderFrontRegardless()
    }

    // A recording left open must not leave the global shortcuts unregistered or swallow a key
    // typed somewhere else, so it ends whenever this window stops being the one typed into.
    func windowWillClose(_ notification: Notification) { environment.cancelRecording() }
    func windowDidResignKey(_ notification: Notification) { environment.cancelRecording() }
}

struct SettingsView: View {
    @ObservedObject var environment: AppEnvironment
    @ObservedObject var modules: ModuleManager
    @AppStorage("settings.lastPane") private var lastPane = SettingsPane.general.rawValue

    /// The page to draw: a module's page that went away with its module falls back to the features.
    private var pane: SettingsPane {
        if case .module(let id) = environment.settingsPane, modules.module(id: id) == nil { return .features }
        return environment.settingsPane
    }

    var body: some View {
        HStack(spacing: 0) {
            SettingsSidebar(modules: modules, selection: Binding(get: { pane }, set: { pane in
                environment.settingsPane = pane
                lastPane = pane.rawValue
                NSApp.keyWindow?.title = "\(pane.title(modules)) – \(AppIdentity.name)"
            }))
            Group {
                switch pane {
                case .general: GeneralPane(environment: environment, settings: environment.settings)
                case .features: FeaturesPane(environment: environment, modules: modules, settings: environment.settings)
                case .menuBar: MenuBarPane(environment: environment, modules: modules, settings: environment.settings)
                case .hotkeys: HotkeysPane(environment: environment, settings: environment.settings)
                case .permissions: PermissionsPane(modules: modules)
                case .privacy: PrivacyPane(environment: environment, modules: modules, settings: environment.settings)
                case .about: AboutPane(environment: environment)
                case .module(let id):
                    if let module = modules.module(id: id) {
                        ModuleSettingsScreen(environment: environment, modules: modules, settings: environment.settings, module: module)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .id(pane)
        }
        .frame(minWidth: SettingsWindowController.size.width, maxWidth: .infinity, minHeight: SettingsWindowController.size.height, maxHeight: .infinity)
        .glassSurface(corner: 18)
        .ignoresSafeArea()
        .onAppear {
            // A pane chosen by whoever opened the window wins; otherwise the last one looked at.
            if environment.settingsPane == .general { environment.settingsPane = SettingsPane(rawValue: lastPane) }
        }
    }
}

private struct SettingsSidebar: View {
    @ObservedObject var modules: ModuleManager
    @Binding var selection: SettingsPane

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Space.m) {
                AppIconImage(size: 34)
                VStack(alignment: .leading, spacing: 1) {
                    Text(AppIdentity.name).font(.role(.body, weight: .semibold))
                    Text("설정").font(.role(.detail)).foregroundStyle(Ink.tertiary)
                }
            }
            .padding(.horizontal, Space.m)
            .padding(.top, Space.huge)
            .padding(.bottom, Space.l)
            ScrollView {
                VStack(alignment: .leading, spacing: Space.xs) {
                    ForEach(Array(SettingsPane.groups(modules).enumerated()), id: \.offset) { _, group in
                        if let title = group.0 {
                            Text(title).font(.role(.detail, weight: .medium)).foregroundStyle(Ink.disabled)
                                .padding(.horizontal, Space.m).padding(.top, Space.l).padding(.bottom, Space.xs)
                        }
                        ForEach(group.1) { item($0) }
                    }
                    // Inside the list, so it never covers the last items when the list is long.
                    item(.about).padding(.top, Space.l)
                }
                .padding(.bottom, Space.m)
            }
            .scrollIndicators(.automatic)
        }
        .padding(.horizontal, Space.m)
        .frame(width: 222)
        .frame(maxHeight: .infinity)
        .background(Shade.medium)
        .overlay(alignment: .trailing) { Line.subtle.frame(width: 1) }
    }

    private func item(_ pane: SettingsPane) -> some View {
        let selected = pane == selection
        return Button { selection = pane } label: {
            HStack(spacing: Space.s) {
                IconTile(symbol: pane.symbol(modules), color: pane.color(modules))
                Text(pane.title(modules)).font(.role(.body)).lineLimit(1)
                Spacer(minLength: 0)
            }
            .foregroundStyle(selected ? Color.white : Ink.secondary)
            .padding(.horizontal, Space.s)
            .frame(height: 32)
            .background(selected ? Fill.selected : Color.clear, in: RoundedRectangle(cornerRadius: Radius.s, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
