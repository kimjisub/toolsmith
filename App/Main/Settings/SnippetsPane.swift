import SwiftUI
import ToolsmithKit

/// Settings → Snippets: the list of snippets on the left, the one being written on the right.
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
            SettingsLead(text: String(localized: "Put a variable in braces, like {name}, and you’re asked for its value when you paste. Snippets are saved only on this Mac and never sent anywhere."))
            if store.loadFailed {
                Notice(text: String(localized: "The saved snippets file couldn’t be read, so the list opened empty. The original file was kept in the same folder as snippets.broken.json."))
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
        .confirmationDialog("Delete the snippet “\(selected?.name ?? "")”?", isPresented: $confirmingDelete) {
            Button("Delete", role: .destructive, action: deleteSelected)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Its shortcut is deleted too. You can’t undo this.")
        }
    }

    // MARK: Empty

    private var emptyState: some View {
        SettingsSection(title: String(localized: "Example"), footer: String(localized: "Anything in braces asks for a value when you paste.")) {
            EmptyState(symbol: "text.quote", title: String(localized: "No Snippets Yet"),
                       detail: String(localized: "Add text you write again and again, then paste it from the launcher or with a shortcut."),
                       action: (String(localized: "Add Snippet"), startDraft))
            ContentRow {
                VStack(alignment: .leading, spacing: Space.s) {
                    Text(Self.exampleName).font(.role(.body, weight: .semibold))
                    Text(Self.exampleBody).font(.role(.secondary, design: .monospaced)).foregroundStyle(Ink.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private static var exampleName: String { String(localized: "First contact") }
    private static var exampleBody: String { String(localized: "Hi {name}, this is {my name}.\nI’m reaching out about the {position:backend} role.") }

    // MARK: List

    private var list: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Card(padding: Space.xs) {
                VStack(spacing: Space.xs) {
                if isDraft { listRow(title: name.isEmpty ? String(localized: "New Snippet") : name, detail: "", selected: true) {} }
                ForEach(snippets) { snippet in
                    listRow(title: snippet.name, detail: snippet.firstLine, selected: !isDraft && snippet.id == selection) { select(snippet) }
                }
                }
            }
            RowButton(String(localized: "Add Snippet"), action: startDraft).disabled(isDraft)
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
            SettingsSection(title: String(localized: "Name")) {
                TextField("e.g. First contact", text: $name)
                    .textFieldStyle(.plain)
                    .font(.role(.body))
                    .focused($nameFocused)
                    .padding(.horizontal, Space.l)
                    .padding(.vertical, Space.m)
            }
            SettingsSection(title: String(localized: "Content"), footer: Self.help) {
                ZStack(alignment: .topLeading) {
                    if text.isEmpty {
                        Text("Write the text to paste. Wrap a word in braces, like {name}, to be asked for it when you paste.")
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
                SettingsSection(title: String(localized: "Shortcut")) {
                    HotkeyRow(environment: environment, action: HotkeyAction(id: snippet.commandID, title: snippet.name, group: String(localized: "Snippets"), detail: snippet.firstLine),
                              title: String(localized: "Shortcut"), detail: String(localized: "Pastes right away when there are no variables; otherwise asks for their values first"))
                }
                RowButton(String(localized: "Delete…"), role: .destructive) { confirmingDelete = true }
            }
        }
        .onChange(of: name) { _, _ in save() }
        .onChange(of: text) { _, _ in save() }
    }

    private static var help: String {
        String(localized: "{name} asks for a value when you paste; {name:default} fills in a default.\nTo type a brace itself, double it: {{ and }}.")
    }

    /// What the text will ask for.
    private var detected: String {
        let template = SnippetTemplate(text)
        return template.variables.isEmpty ? String(localized: "No variables.") : String(localized: "Asks for: \(template.variables.map(\.name).joined(separator: ", "))")
    }

    /// Why what is on screen is not what is saved, if so.
    private var status: String? {
        if isDraft { return String(localized: "Not saved yet. It’s saved once it has both a name and text.") }
        if selected != nil, !isValid { return String(localized: "Not saved: the name or the text is empty. Fill in both to save.") }
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
