import SwiftUI
import ToolsmithKit

/// Capture in the menu bar panel: every capture action as a tile, two to a row. Picking one closes
/// the panel first, so the panel is not in the picture.
struct CapturePanelScreen: View {
    let commands: [Command]
    let isRecording: Bool
    let run: (Command) -> Void

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: Space.s), GridItem(.flexible(), spacing: Space.s)], spacing: Space.s) {
            ForEach(commands) { command in
                ActionTile(command: command, highlighted: isRecording && command.id == CaptureCommandSource.stopID) { run(command) }
            }
        }
        .padding(Space.m)
    }
}

private struct ActionTile: View {
    let command: Command
    let highlighted: Bool
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: Space.s) {
                if case .symbol(let name) = command.icon {
                    Image(systemName: name).font(.role(.body)).foregroundStyle(highlighted ? Status.danger : Brand.accent).frame(width: IconSize.app)
                }
                Text(command.title).font(.role(.secondary)).lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Space.m)
            .frame(height: 36)
            .background(hovered ? Fill.selected : Fill.card, in: RoundedRectangle(cornerRadius: Radius.s, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Radius.s, style: .continuous).strokeBorder(Line.subtle, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
    }
}
