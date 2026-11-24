import AppKit
import SwiftUI
import ToolsmithKit

/// The clipboard in the menu bar panel: the latest copies, one click to paste one into the app in
/// front. The full history (search, previews, pins) stays in the shelf, which opens from here.
struct ClipboardPanelScreen: View {
    let items: [ClipItem]
    let onPaste: (ClipItem) -> Void
    let onOpenShelf: () -> Void
    static let count = 10

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if items.isEmpty {
                EmptyState(symbol: "doc.on.clipboard", title: "아직 복사한 것이 없습니다", detail: "무언가를 복사하면 여기에 쌓입니다.")
            } else {
                VStack(spacing: Space.xs) {
                    ForEach(items) { item in ClipRow(item: item) { onPaste(item) } }
                }
                .padding(Space.s)
            }
            Line.subtle.frame(height: 1)
            HStack {
                Text("누르면 쓰던 앱에 붙여 넣습니다").textRole(.detail).foregroundStyle(Ink.tertiary)
                Spacer(minLength: Space.s)
                RowButton("기록 전체 보기", action: onOpenShelf)
            }
            .padding(.horizontal, Space.l)
            .padding(.vertical, Space.s)
        }
    }
}

private struct ClipRow: View {
    let item: ClipItem
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: Space.m) {
                Image(systemName: ClipboardCommandSource.symbol(of: item))
                    .font(.role(.body)).foregroundStyle(Ink.secondary).frame(width: IconSize.tile)
                VStack(alignment: .leading, spacing: 0) {
                    Text(ClipboardCommandSource.title(of: item)).font(.role(.body)).lineLimit(1)
                    Text([item.sourceName, RelativeTime.text(from: item.copiedAt, now: Date())].compactMap { $0 }.joined(separator: " · "))
                        .font(.role(.detail)).foregroundStyle(Ink.tertiary).lineLimit(1)
                }
                Spacer(minLength: 0)
                if item.pinned { Image(systemName: "pin.fill").font(.role(.detail)).foregroundStyle(Brand.accent) }
            }
            .padding(.horizontal, Space.s)
            .padding(.vertical, Space.xs)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(hovered ? Fill.selected : Color.clear, in: RoundedRectangle(cornerRadius: Radius.s, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
    }
}
