import SwiftUI
import ToolsmithKit

/// Settings → 스니펫: the list of snippets on the left, the one being written on the right.
struct SnippetsPane: View {
    @ObservedObject var environment: AppEnvironment
    @ObservedObject var module: SnippetsModule
    @ObservedObject var settings: SettingsStore

    @State private var snippets: [Snippet] = []
    /// The saved snippet in the editor. nil with `isDraft` is a new snippet not saved yet.
    @State private var selection: UUID?
    @State private var isDraft = false
    @State private var name = ""
    @State private var text = ""
    @State private var confirmingDelete = false
    @FocusState private var nameFocused: Bool

    private var store: SnippetStore { module.store }
    private var selected: Snippet? { selection.flatMap { id in snippets.first { $0.id == id } } }
    private var isValid: Bool { Snippet.isValid(name: name, body: text) }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xxl) {
            SettingsLead(text: "{이름} 처럼 중괄호로 변수를 넣으면 붙일 때 값을 물어 채워 줍니다. 스니펫은 이 맥에만 저장되고 다른 곳으로 보내지 않습니다.")
            if store.loadFailed {
                Notice(text: "저장된 스니펫 파일을 읽지 못해 빈 상태로 열었습니다. 원래 파일은 지우지 않고 같은 폴더에 snippets.broken.json 으로 남겨 두었습니다.")
            }
            if snippets.isEmpty, !isDraft {
                emptyState
            } else {
                HStack(alignment: .top, spacing: Space.l) {
                    list.frame(width: 190)
                    editor.frame(maxWidth: .infinity)
                }
            }
        }
        .onAppear(perform: appear)
        .onChange(of: module.draftRequested) { _, requested in if requested { startDraft() } }
        .onDisappear { environment.cancelRecording() }
        .confirmationDialog("「\(selected?.name ?? "")」 스니펫을 지울까요?", isPresented: $confirmingDelete) {
            Button("지우기", role: .destructive, action: deleteSelected)
            Button("취소", role: .cancel) {}
        } message: {
            Text("스니펫과 함께 걸어 둔 단축키도 지워지며, 되돌릴 수 없습니다.")
        }
    }

    // MARK: Empty

    private var emptyState: some View {
        SettingsSection(title: "예시", footer: "중괄호로 감싼 곳은 붙일 때 값을 묻습니다.") {
            EmptyState(symbol: "text.quote", title: "아직 스니펫이 없습니다",
                       detail: "자주 쓰는 멘트를 추가하면 입력창이나 단축키로 바로 붙일 수 있습니다.",
                       action: ("스니펫 추가", startDraft))
            ContentRow {
                VStack(alignment: .leading, spacing: Space.s) {
                    Text(Self.exampleName).font(.role(.body, weight: .semibold))
                    Text(Self.exampleBody).font(.role(.secondary, design: .monospaced)).foregroundStyle(Ink.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private static let exampleName = "첫 연락 인사"
    private static let exampleBody = "{이름}님 안녕하세요, {내 이름}입니다.\n{포지션:백엔드} 포지션으로 연락드립니다."

    // MARK: List

    private var list: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Card(padding: Space.xs) {
                VStack(spacing: Space.xs) {
                if isDraft { listRow(title: name.isEmpty ? "새 스니펫" : name, detail: "", selected: true) {} }
                ForEach(snippets) { snippet in
                    listRow(title: snippet.name, detail: snippet.firstLine, selected: !isDraft && snippet.id == selection) { select(snippet) }
                }
                }
            }
            RowButton("스니펫 추가", action: startDraft).disabled(isDraft)
        }
    }

    private func listRow(title: String, detail: String, selected: Bool, action: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Text(title).font(.role(.body, weight: selected ? .semibold : .regular)).lineLimit(1)
            if !detail.isEmpty {
                Text(detail).font(.role(.detail)).foregroundStyle(Ink.tertiary).lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Space.m)
        .padding(.vertical, Space.s)
        .background(selected ? Fill.selected : Color.clear, in: RoundedRectangle(cornerRadius: Radius.s, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture(perform: action)
    }

    // MARK: Editor

    private var editor: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            SettingsSection(title: "이름") {
                TextField("예: 첫 연락 인사", text: $name)
                    .textFieldStyle(.plain)
                    .font(.role(.body))
                    .focused($nameFocused)
                    .padding(.horizontal, Space.l)
                    .padding(.vertical, Space.m)
            }
            SettingsSection(title: "내용", footer: Self.help) {
                ZStack(alignment: .topLeading) {
                    if text.isEmpty {
                        Text("붙여 넣을 멘트를 적으세요. {이름} 처럼 중괄호로 감싸면 붙일 때 값을 묻습니다.")
                            .font(.role(.body)).foregroundStyle(Ink.tertiary)
                            .padding(.horizontal, Space.xs).padding(.vertical, 1)
                            .allowsHitTesting(false)
                    }
                    TextEditor(text: $text)
                        .font(.role(.body))
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 150)
                }
                .padding(.horizontal, Space.s)
                .padding(.vertical, Space.m)
                SettingsRow(title: detected)
            }
            if let status {
                Text(status).font(.role(.secondary)).foregroundStyle(Status.warning).padding(.horizontal, Space.xs)
            }
            if let snippet = selected, !isDraft {
                SettingsSection(title: "단축키") {
                    HotkeyRow(environment: environment, action: HotkeyAction(id: snippet.commandID, title: snippet.name, group: "스니펫", detail: snippet.firstLine),
                              title: "단축키", detail: "변수가 없으면 바로 붙고, 있으면 값을 묻는 화면이 뜹니다")
                }
                RowButton("지우기…", role: .destructive) { confirmingDelete = true }
            }
        }
        .onChange(of: name) { _, _ in save() }
        .onChange(of: text) { _, _ in save() }
    }

    private static let help = """
    {이름} 은 붙일 때 값을 묻고, {이름:기본값} 처럼 쓰면 기본값이 미리 채워집니다.
    중괄호 글자 자체를 넣고 싶으면 {{ 와 }} 처럼 두 번 겹쳐 씁니다.
    """

    /// What the text will ask for.
    private var detected: String {
        let template = SnippetTemplate(text)
        return template.variables.isEmpty ? "변수가 없습니다." : "묻는 것: " + template.variables.map(\.name).joined(separator: ", ")
    }

    /// Why what is on screen is not what is saved, if so.
    private var status: String? {
        if isDraft { return "아직 저장되지 않았습니다. 이름과 내용을 모두 쓰면 저장됩니다." }
        if selected != nil, !isValid { return "이름이나 내용이 비어 있어 저장되지 않았습니다. 둘 다 채워야 저장됩니다." }
        return nil
    }

    // MARK: Changes

    private func appear() {
        snippets = store.snippets
        if module.draftRequested {
            startDraft()
        } else if selection == nil || selected == nil, let first = snippets.first {
            select(first)
        }
    }

    private func select(_ snippet: Snippet) {
        environment.cancelRecording()
        isDraft = false
        selection = snippet.id
        name = snippet.name
        text = snippet.body
    }

    private func startDraft() {
        module.draftRequested = false
        environment.cancelRecording()
        isDraft = true
        selection = nil
        name = ""
        text = ""
        nameFocused = true
    }

    /// Saves as it is typed. A new snippet is saved the moment it has both a name and a text;
    /// an emptied one keeps what was saved last.
    private func save() {
        guard isValid else { return }
        if isDraft {
            guard let made = store.add(name: name, body: text) else { return }
            isDraft = false
            selection = made.id
        } else if let id = selection {
            guard let saved = store.snippet(id), saved.name != name || saved.body != text else { return }
            store.update(id, name: name, body: text)
        } else {
            return
        }
        snippets = store.snippets
        module.snippetsChanged()
    }

    private func deleteSelected() {
        guard let id = selection else { return }
        module.deleteSnippet(id)
        snippets = store.snippets
        selection = nil
        if let first = snippets.first { select(first) } else { name = ""; text = "" }
    }
}
