import SwiftUI
import ToolsmithKit

/// Whether the launcher is on screen, and how tall it may grow there.
@MainActor final class LauncherPresentation: ObservableObject {
    @Published var isShown = false
    @Published var maxHeight: CGFloat = 520
    /// One line shown instead of the launcher (why an action could not be done).
    @Published var notice: String?
}

struct LauncherView: View {
    @ObservedObject var model: LauncherModel
    @ObservedObject var settings: SettingsStore
    @ObservedObject var presentation: LauncherPresentation
    @ObservedObject var ai: AISession
    /// Whether a key is available, asked when the AI row is drawn.
    var hasAIKey: () -> Bool = { true }
    var onCommand: (QueryCommand) -> Void
    var onPick: (String) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let queryRowHeight: CGFloat = 64
    private static let hintHeight: CGFloat = 34
    private static let listPadding: CGFloat = 8

    private var rowIDs: [String] { model.visibleIDs }
    private var noResults: Bool { rowIDs.isEmpty && !model.query.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        VStack(spacing: 0) {
            if let notice = presentation.notice {
                HStack(spacing: Space.m) {
                    Image(systemName: "exclamationmark.circle").font(.role(.heading)).foregroundStyle(Status.warning)
                    Text(notice).font(.role(.emphasis)).foregroundStyle(Ink.primary)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, Space.xl)
                .frame(minHeight: Self.queryRowHeight)
            } else {
                content
            }
        }
        .frame(width: Theme.panelWidth)
        .glassSurface()
        .shadow(color: Shade.strong, radius: 34, y: 18)
        .scaleEffect(presentation.isShown || reduceMotion ? 1 : 0.97, anchor: .top)
        .opacity(presentation.isShown ? 1 : 0)
        .animation(.easeOut(duration: presentation.isShown ? Theme.appear : Theme.disappear), value: presentation.isShown)
        .animation(reduceMotion ? nil : .spring(response: 0.26, dampingFraction: 0.86), value: rowIDs)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .environment(\.colorScheme, .dark)
    }

    @ViewBuilder private var content: some View {
        if model.mode == .fill, let fill = model.fill {
            // A new fill gets new fields: nothing typed, or still being composed, carries over.
            SnippetFillView(model: model, fill: fill, maxHeight: presentation.maxHeight, onCommand: onCommand)
                .id(fill.session)
        } else {
            searchContent
        }
    }

    @ViewBuilder private var searchContent: some View {
            queryRow
            if model.mode == .ai {
                if !ai.isEmpty {
                    Line.subtle.frame(height: 1)
                    AIAnswerView(session: ai, maxHeight: max(160, presentation.maxHeight - Self.queryRowHeight - Self.hintHeight))
                }
                aiHint
            } else if !rowIDs.isEmpty {
                Line.subtle.frame(height: 1)
                list
                aiRow
                hint
            } else if noResults {
                Line.subtle.frame(height: 1)
                Text("결과 없음")
                    .font(.role(Theme.rowRole))
                    .foregroundStyle(Ink.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Space.xl)
                    .frame(height: Theme.rowHeight + 8)
                aiRow
            }
    }

    /// "AI 에게 묻기": always the last row, never selected unless the user goes there.
    @ViewBuilder private var aiRow: some View {
        if model.showsAIRow {
            let selected = model.selectedID == LauncherModel.aiRowID
            HStack(spacing: Space.m) {
                Image(systemName: "sparkles").font(.role(.emphasis, weight: .medium)).foregroundStyle(Brand.lavender).frame(width: 24, height: 24)
                Text("AI 에게 묻기").font(.role(Theme.rowRole)).foregroundStyle(selected ? Color.white : Ink.secondary)
                Text(model.query.trimmingCharacters(in: .whitespaces)).font(.role(.body)).foregroundStyle(Ink.tertiary).lineLimit(1)
                Spacer(minLength: Space.s)
                if !hasAIKey() { Text("키 필요").font(.role(.secondary)).foregroundStyle(Status.warning) }
                KeyCap(label: "⇥", highlighted: selected)
            }
            .padding(.leading, Space.m)
            .padding(.trailing, Space.l)
            .frame(height: Theme.rowHeight)
            .background {
                if selected {
                    RoundedRectangle(cornerRadius: Radius.m, style: .continuous)
                        .fill(Fill.selected)
                        .overlay(RoundedRectangle(cornerRadius: Radius.m, style: .continuous).strokeBorder(Tint.light(Brand.glow), lineWidth: 1))
                        .shadow(color: Tint.light(Brand.glow), radius: 11)
                }
            }
            .padding(.horizontal, Self.listPadding)
            .padding(.bottom, Space.xs)
            .contentShape(Rectangle())
            .onTapGesture {
                model.selectAIRow()
                onCommand(.submit)
            }
        }
    }

    private var aiHint: some View {
        HStack(spacing: Space.xs) {
            if ai.isStreaming {
                KeyCap(label: "esc"); Text("멈추기")
            } else {
                KeyCap(label: "↵"); Text(ai.isEmpty ? "묻기" : "이어서 묻기")
                if !ai.isEmpty {
                    KeyCap(label: "⌘").padding(.leading, Space.m); KeyCap(label: "C"); Text("답 복사")
                }
            }
            Spacer()
            if !hasAIKey() { Text("OpenRouter 키가 필요합니다. ↵ 를 누르면 설정이 열립니다").foregroundStyle(Status.warning) }
            if !ai.isStreaming { KeyCap(label: "esc").padding(.leading, Space.s); Text("돌아가기") }
        }
        .font(.role(.detail))
        .foregroundStyle(Ink.tertiary)
        .padding(.horizontal, Space.xl)
        .frame(height: Self.hintHeight)
        .background(Shade.soft)
    }

    // MARK: Query

    private var queryRow: some View {
        HStack(spacing: Space.m) {
            if model.mode == .ai {
                HStack(spacing: Space.xs) {
                    Image(systemName: "sparkles").font(.role(.detail, weight: .semibold))
                    Text("AI").font(.role(.secondary, weight: .semibold))
                }
                .foregroundStyle(Brand.lavender)
                .padding(.horizontal, Space.m)
                .padding(.vertical, Space.xs)
                .background(Tint.wash(Brand.lavender), in: Capsule())
            }
            if model.mode == .snippets {
                HStack(spacing: Space.xs) {
                    Image(systemName: "text.quote").font(.role(.detail, weight: .semibold))
                    Text("스니펫").font(.role(.secondary, weight: .semibold))
                }
                .foregroundStyle(Ink.secondary)
                .padding(.horizontal, Space.m)
                .padding(.vertical, Space.xs)
                .background(Fill.selected, in: Capsule())
            }
            GradientQueryField(text: $model.query, placeholder: placeholder,
                               role: Theme.queryRole, capturesTab: true, gradient: model.mode == .ai, onCommand: onCommand)
        }
        .padding(.horizontal, Space.xl)
        .frame(height: Self.queryRowHeight)
    }

    private var placeholder: String {
        switch model.mode {
        case .ai: return ai.isEmpty ? "무엇이든 물어보세요" : "이어서 묻기"
        case .snippets: return "스니펫 검색"
        case .commands, .fill: return "무엇을 할까요"
        }
    }

    // MARK: Results

    private var listHeight: CGFloat {
        let rows = CGFloat(rowIDs.count) * Theme.rowHeight
        let headers = CGFloat(model.sections.count) * Theme.sectionHeaderHeight
        let wanted = rows + headers + Self.listPadding * 2
        return min(wanted, max(Theme.rowHeight * 3, presentation.maxHeight - Self.queryRowHeight - Self.hintHeight))
    }

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                VStack(spacing: 0) {
                    ForEach(model.sections, id: \.section) { section in
                        sectionView(section)
                    }
                }
                .padding(Self.listPadding)
            }
            .scrollIndicators(.never)
            .frame(height: listHeight)
            .onChange(of: model.selectedID) { _, id in
                guard let id else { return }
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.12)) { proxy.scrollTo(id, anchor: nil) }
            }
        }
    }

    private func sectionView(_ section: ResultSection) -> some View {
        VStack(spacing: 0) {
            Text(section.section.title)
                .font(.role(.detail))
                .foregroundStyle(Ink.disabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Space.m)
                .frame(height: Theme.sectionHeaderHeight)
            VStack(spacing: 0) {
                ForEach(section.commandIDs, id: \.self) { id in
                    if let command = model.command(id: id) {
                        row(command).id(id)
                    }
                }
            }
        }
    }

    private func number(of id: String) -> Int? {
        rowIDs.firstIndex(of: id).map { $0 + 1 }
    }

    /// Rows further down are dimmer; the selected one is always full strength.
    private func strength(of id: String) -> Double {
        guard id != model.selectedID, let index = rowIDs.firstIndex(of: id) else { return 1 }
        return index < 2 ? 1 : (index == 2 ? 0.75 : 0.5)
    }

    private func row(_ command: Command) -> some View {
        let selected = command.id == model.selectedID
        let index = number(of: command.id)
        return HStack(spacing: Space.m) {
            CommandIconView(icon: command.icon)
            Text(command.title)
                .font(.role(Theme.rowRole))
                .foregroundStyle(selected ? Color.white : Ink.secondary)
                .lineLimit(1)
            if let subtitle = command.subtitle {
                Text(subtitle).font(.role(.secondary)).foregroundStyle(Ink.tertiary).lineLimit(1).truncationMode(.middle)
            }
            Spacer(minLength: Space.s)
            if let hotkeyID = command.hotkeyID, let combo = settings.settings.hotkeys.combo(for: hotkeyID) {
                Text(combo.display)
                    .font(.role(.secondary, design: .monospaced))
                    .foregroundStyle(Ink.disabled)
            } else if let shortcut = command.launcherShortcut {
                Text(shortcut)
                    .font(.role(.secondary, design: .monospaced))
                    .foregroundStyle(Ink.disabled)
            }
            if let index, index <= 9 {
                // The ⌘ is shown with the number: the number alone does nothing.
                KeyCap(label: "⌘\(index)", highlighted: selected)
            } else {
                KeyCap(label: "⌘9").hidden() // keeps the column for rows past the ninth
            }
        }
        .padding(.leading, Space.m)
        .padding(.trailing, Space.l)
        .frame(height: Theme.rowHeight)
        .background {
            if selected {
                RoundedRectangle(cornerRadius: Radius.m, style: .continuous)
                    .fill(Fill.selected)
                    .overlay(RoundedRectangle(cornerRadius: Radius.m, style: .continuous).strokeBorder(Tint.light(Brand.glow), lineWidth: 1))
                    .shadow(color: Tint.light(Brand.glow), radius: 11)
            }
        }
        .opacity(strength(of: command.id))
        .contentShape(Rectangle())
        .onTapGesture { onPick(command.id) }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var hint: some View {
        HStack(spacing: Space.xs) {
            KeyCap(label: "⌘")
            Text("와 숫자를 누르면 그 줄이 바로 실행됩니다")
            Spacer()
            KeyCap(label: "↵")
            Text("실행")
            KeyCap(label: "esc").padding(.leading, Space.s)
            Text(model.mode == .snippets && model.snippetSearchReturnsToList ? "돌아가기" : "닫기")
        }
        .font(.role(.detail))
        .foregroundStyle(Ink.tertiary)
        .padding(.horizontal, Space.xl)
        .frame(height: Self.hintHeight)
        .background(Shade.soft)
    }
}

struct CommandIconView: View {
    let icon: CommandIcon

    var body: some View {
        switch icon {
        case .symbol(let name):
            Image(systemName: name)
                .font(.role(.emphasis, weight: .medium))
                .foregroundStyle(Ink.secondary)
                .frame(width: 24, height: 24)
        case .file(let url):
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                .resizable()
                .frame(width: 24, height: 24)
        }
    }
}
