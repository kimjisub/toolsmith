import SwiftUI
import ToolsmithKit

/// A row that shows an action's global shortcut and takes a new one: click it, press keys. esc
/// cancels, ⌫ clears. A key that belongs to another action asks before it moves. The one row for
/// shortcuts everywhere in the settings (the shortcuts page, a module's Shortcuts group, a snippet).
struct HotkeyRow: View {
    @ObservedObject var environment: AppEnvironment
    /// Observed too: the table lives in the settings, not in the environment.
    @ObservedObject private var settings: SettingsStore
    let action: HotkeyAction
    /// Shown instead of the action's title ("Shortcut" under a snippet that already says its name).
    var title: String?
    var detail: String?

    init(environment: AppEnvironment, action: HotkeyAction, title: String? = nil, detail: String? = nil) {
        self.environment = environment
        settings = environment.settings
        self.action = action
        self.title = title
        self.detail = detail
    }

    @State private var pendingMove: (combo: KeyCombo, owner: HotkeyAction)?
    @State private var message: String?

    private var table: HotkeyTable { settings.settings.hotkeys }
    private var isRecording: Bool { environment.recordingHotkeyID == action.id }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            HStack(spacing: Space.l) {
                VStack(alignment: .leading, spacing: Space.xs) {
                    Text(title ?? action.title).font(.role(.body)).lineLimit(1)
                    if let detail = detail ?? action.detail, !detail.isEmpty {
                        Text(detail).font(.role(.detail)).foregroundStyle(Ink.tertiary).lineLimit(2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                keys
            }
            footnote
        }
        .padding(.horizontal, Space.l)
        .padding(.vertical, Space.m)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .onTapGesture(perform: beginRecording)
        .accessibilityAddTraits(.isButton)
    }

    @ViewBuilder private var keys: some View {
        if isRecording {
            Text("Press keys…").font(.role(.secondary)).foregroundStyle(Status.warning)
        } else if let combo = table.combo(for: action.id) {
            KeyCaps(parts: combo.displayParts)
        } else {
            Text("Add Shortcut")
                .font(.role(.secondary))
                .foregroundStyle(Ink.tertiary)
                .padding(.horizontal, Space.s)
                .padding(.vertical, Space.xs)
                .overlay(RoundedRectangle(cornerRadius: Radius.xs, style: .continuous).strokeBorder(Line.strong, style: StrokeStyle(lineWidth: 1, dash: [3])))
        }
    }

    @ViewBuilder private var footnote: some View {
        if let pendingMove {
            HStack(spacing: Space.s) {
                Text("\(pendingMove.combo.display) is the shortcut for “\(Self.name(of: pendingMove.owner))”. Move it to this action?")
                    .font(.role(.secondary)).foregroundStyle(Status.warning).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: Space.xs)
                RowButton(String(localized: "Move")) {
                    environment.settings.update { $0.hotkeys.reassign(pendingMove.combo, to: action.id) }
                    self.pendingMove = nil
                }
                RowButton(String(localized: "Cancel")) { self.pendingMove = nil }
            }
        } else if let message {
            Text(message).font(.role(.secondary)).foregroundStyle(Status.warning)
        } else if !isRecording, let combo = table.combo(for: action.id),
                  let notice = HotkeyCatalog.notice(for: combo, id: action.id, system: environment.systemShortcuts, failed: environment.failedHotkeys) {
            Text(notice == .systemShortcut ? "This is also a macOS system shortcut." : "Another app already uses this shortcut, so it couldn’t be registered.")
                .font(.role(.secondary)).foregroundStyle(Status.warning)
        }
    }

    /// An action's name as the "move it here?" question shows it. A snippet carries its first line.
    static func name(of action: HotkeyAction) -> String {
        guard action.id.hasPrefix(Snippet.commandPrefix), let detail = action.detail, !detail.isEmpty else { return action.title }
        return "\(action.title) · \(detail)"
    }

    private func beginRecording() {
        pendingMove = nil
        message = nil
        let id = action.id
        environment.beginRecording(id) { key in
            let actions = HotkeyCatalog.actions(from: environment.engine.hotkeyCommands())
            switch HotkeyAssignment.apply(key, to: id, settings: environment.settings, actions: actions) {
            case .done: break
            case .message(let text): message = text
            case .askMove(let combo, let owner): pendingMove = (combo, owner)
            }
        }
    }
}
