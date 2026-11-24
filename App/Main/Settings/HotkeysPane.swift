import SwiftUI
import ToolsmithKit

/// Settings → 단축키: every global shortcut of the running features, in their groups.
struct HotkeysPane: View {
    @ObservedObject var environment: AppEnvironment
    @ObservedObject var settings: SettingsStore
    @State private var search = ""

    private var actions: [HotkeyAction] { HotkeyCatalog.actions(from: environment.engine.hotkeyCommands()) }

    var body: some View {
        let others = HotkeyCatalog.filter(actions.filter { $0.id != HotkeyID.openLauncher }, query: search)
        SettingsPage(title: "단축키", lead: "줄을 누르고 원하는 키를 누르면 바뀝니다. esc 는 취소, ⌫ 는 단축키 지우기입니다. 꺼 둔 기능의 단축키는 여기에 없고, 다시 켜면 돌아옵니다.") {
            if environment.modules.isEnabled(LauncherModule.descriptor.id) {
                SettingsSection(title: "입력창", footer: "다른 모든 것은 입력창에서 시작합니다. 비워 둘 수 없습니다.") {
                    HotkeyRow(environment: environment, action: HotkeyCatalog.launcher)
                }
            }
            TextField("동작 찾기", text: $search).textFieldStyle(.roundedBorder)
            ForEach(HotkeyCatalog.grouped(others), id: \.group) { group in
                SettingsSection(title: group.group) {
                    ForEach(group.actions) { HotkeyRow(environment: environment, action: $0) }
                }
            }
            if others.isEmpty {
                Card { EmptyState(symbol: "command", title: search.isEmpty ? "단축키를 줄 수 있는 동작이 아직 없습니다" : "찾는 동작이 없습니다") }
            }
        }
        .onDisappear { environment.cancelRecording() }
    }
}

/// What a recorded key does to the shortcut table. Shared by every place that records one.
@MainActor enum HotkeyAssignment {
    enum Outcome {
        case done
        /// Why the key was not accepted.
        case message(String)
        /// The key belongs to another action: ask before moving it.
        case askMove(KeyCombo, HotkeyAction)
    }

    static func apply(_ key: RecordedKey, to id: String, settings: SettingsStore, actions: [HotkeyAction]) -> Outcome {
        switch key {
        case .cancel:
            return .done
        case .clear:
            do {
                try settings.updateHotkeys { try $0.clear(id) }
                return .done
            } catch {
                return .message("입력창 단축키는 비울 수 없습니다.")
            }
        case .combo(let combo):
            var copy = settings.settings.hotkeys
            switch copy.assign(combo, to: id) {
            case .assigned:
                settings.update { $0.hotkeys = copy }
                return .done
            case .invalid:
                return .message("⌃, ⌥, ⌘ 중 하나를 함께 누르세요.")
            case .taken(let ownerID):
                if ownerID == HotkeyID.openLauncher {
                    return .message("\(combo.display) 는 입력창 열기의 단축키라 옮길 수 없습니다.")
                } else if let owner = actions.first(where: { $0.id == ownerID }) {
                    return .askMove(combo, owner)
                }
                // The owner is an action that no longer exists: nothing to ask about.
                settings.update { $0.hotkeys.reassign(combo, to: id) }
                return .done
            }
        }
    }
}
