import AppKit
import SwiftUI
import ToolsmithKit

/// 스니펫: written lines pasted into the app in use, with variables asked for in the launcher.
@MainActor final class SnippetsModule: AppModule, ObservableObject {
    nonisolated static let descriptor = ModuleDescriptor(id: "snippets", title: "스니펫", summary: "자주 쓰는 멘트를 저장해 두고 쓰던 앱에 바로 붙입니다",
                                             symbol: "text.quote", tint: .teal, requires: [LauncherModule.descriptor.id], permissions: [.accessibility])
    var descriptor: ModuleDescriptor { Self.descriptor }
    unowned let host: ModuleHost
    let store: SnippetStore
    private let source: SnippetCommandSource
    /// The ⌘V waiting for the panel to let go of the keyboard. A newer run replaces it.
    private var pasteWork: DispatchWorkItem?
    /// Set by 「스니펫 만들기」; the snippets page opens a new snippet when it sees it.
    @Published var draftRequested = false

    init(host: ModuleHost) {
        self.host = host
        var file = SettingsStore.supportDirectory.appendingPathComponent("snippets", isDirectory: true).appendingPathComponent("snippets.json")
        #if TOOLSMITH_DEV
        // Development aid: the snippet search is drawn with made-up snippets, kept away from the real ones.
        if CommandLine.arguments.contains("--snippet-search-demo") {
            file = FileManager.default.temporaryDirectory
                .appendingPathComponent("\(AppIdentity.compactName)-demo-\(UUID().uuidString)", isDirectory: true).appendingPathComponent("snippets.json")
        }
        #endif
        store = SnippetStore(fileURL: file)
        source = SnippetCommandSource(store: store)
        wire()
    }

    var commandSources: [CommandSource] { [source] }
    var settingsShortcutIDs: [String]? { [SnippetCommandSource.searchID] }
    func settingsGroups(in environment: AppEnvironment) -> AnyView? {
        AnyView(SnippetsPane(environment: environment, module: self, settings: environment.settings))
    }

    func start() {}
    func stop() { pasteWork?.cancel() }

    private func wire() {
        source.onInsert = { [weak self] _, template in
            guard let self else { return }
            // The app in front when the run started.
            self.insert(template.render(values: [:]), into: self.host.targetApp)
        }
        source.onFill = { [weak self] snippet in
            guard let self else { return }
            // A paste still waiting must not land in the fields that are about to open.
            self.pasteWork?.cancel()
            // Picked in the launcher, esc goes back to the results. Opened by a shortcut, esc closes.
            self.host.model.beginFill(SnippetFill(snippet: snippet, returnsToList: !self.host.isFiringHotkey))
        }
        host.panel.onSubmitFill = { [weak self] text, target in self?.insert(text, into: target) }
        source.onNew = { [weak self] in self?.openNewSnippet() }
        // Picked in the launcher, esc goes back to the commands. Opened by a shortcut, esc closes.
        source.onSearch = { [weak self] in
            guard let self else { return }
            // A paste still waiting would find the search holding the keyboard and replace it with a notice.
            self.pasteWork?.cancel()
            self.host.model.enterSnippetSearch(returnsToList: !self.host.isFiringHotkey)
        }
    }

    func willRunFromHotkey(_ command: Command) -> Bool {
        guard command.section == SnippetCommandSource.section else { return false }
        // The snippet search's own shortcut, pressed again, puts it away.
        if command.id == SnippetCommandSource.searchID, host.panel.isOpen, host.model.mode == .snippets {
            host.panel.hide()
            return true
        }
        // A floating window holding the keyboard (the clipboard shelf's search) would take the ⌘V.
        host.dismissPanels()
        return false
    }

    /// Puts the text on the clipboard and pastes it into `target`, if that app is still in front.
    private func insert(_ text: String, into target: NSRunningApplication?) {
        pasteWork?.cancel()
        Paster.write(text: text)
        // Give the panel a moment to let go of the keyboard, then press ⌘V for the user.
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            // One of our own windows still has the keyboard: ⌘V would go into it.
            let ownWindowHasKeys = NSApp.windows.contains { $0.isVisible && $0.isKeyWindow }
            guard ownWindowHasKeys || !Paster.pressPaste(into: target) else { return }
            self.host.notify(AccessibilityPermission.isGranted
                ? "쓰던 앱이 바뀌어 복사만 했습니다. ⌘V 로 붙여 넣으세요."
                : "복사했습니다. ⌘V 로 붙여 넣으세요. (손쉬운 사용 권한을 주면 바로 붙습니다)")
        }
        pasteWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.14, execute: work)
    }

    /// 「스니펫 만들기」: the snippets page of the settings, with a new snippet open.
    func openNewSnippet() {
        draftRequested = true
        host.openSettings(.snippets)
    }

    /// Removes a snippet with its shortcut and its place in "최근".
    func deleteSnippet(_ id: UUID) {
        guard let snippet = store.snippet(id) else { return }
        store.remove(id)
        host.settings.update { try? $0.hotkeys.clear(snippet.commandID) }
        host.usage.remove(snippet.commandID)
        snippetsChanged()
    }

    /// A snippet was added, changed or removed: the launcher's commands and the registered shortcuts follow.
    func snippetsChanged() { host.commandsChanged() }
}
