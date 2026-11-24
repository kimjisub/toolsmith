import SwiftUI
import ToolsmithKit

/// AI search settings: the OpenRouter key and the model.
struct AIPane: View {
    @ObservedObject var settings: SettingsStore
    @State private var draftKey = ""
    @State private var hasSavedKey = KeyStore.hasSavedKey
    @State private var message: String?
    @State private var model = ""

    var body: some View {
        SettingsLead(text: String(localized: "Type . at the start of the launcher, or type a question and press ⇥ to choose Ask AI. It searches the web and answers with up-to-date information."))
        SettingsSection(title: String(localized: "OpenRouter Key"),
                        footer: message ?? String(localized: "The key is stored only in this Mac’s keychain. Questions and answers go to and from OpenRouter; \(AppIdentity.name) doesn’t save them.")) {
            SettingsRow(title: hasSavedKey ? String(localized: "Key saved") : String(localized: "Not set"), detail: hasSavedKey ? String(localized: "Enter a new key to replace it") : String(localized: "Paste a key you created at openrouter.ai")) {
                if hasSavedKey {
                    RowButton(String(localized: "Delete"), role: .destructive) {
                        KeyStore.delete()
                        hasSavedKey = false
                        message = String(localized: "The key was deleted from this Mac.")
                    }
                }
            }
            FieldRow(placeholder: "sk-or-…", text: $draftKey, secure: true, monospaced: true,
                     button: (String(localized: "Save"), !draftKey.trimmingCharacters(in: .whitespaces).isEmpty, save), onSubmit: save)
        }
        SettingsSection(title: String(localized: "Model"), footer: String(localized: "An OpenRouter model name. Leave empty to use the default (\(AIRequest.defaultModel)).")) {
            FieldRow(placeholder: AIRequest.defaultModel, text: $model, monospaced: true, onSubmit: saveModel)
                .onChange(of: model) { _, _ in saveModel() }
        }
        .onAppear {
            hasSavedKey = KeyStore.hasSavedKey
            model = settings.settings.aiModel == AIRequest.defaultModel ? "" : settings.settings.aiModel
        }
    }

    private func save() {
        guard KeyStore.save(draftKey) else {
            message = String(localized: "Couldn’t save the key.")
            return
        }
        draftKey = ""
        hasSavedKey = true
        message = String(localized: "Saved.")
    }

    private func saveModel() {
        let trimmed = model.trimmingCharacters(in: .whitespaces)
        settings.update { $0.aiModel = trimmed.isEmpty ? AIRequest.defaultModel : trimmed }
    }
}
