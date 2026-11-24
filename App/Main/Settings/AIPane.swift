import SwiftUI
import ToolsmithKit

/// AI 검색 settings: the OpenRouter key and the model.
struct AIPane: View {
    @ObservedObject var settings: SettingsStore
    @State private var draftKey = ""
    @State private var hasSavedKey = KeyStore.hasSavedKey
    @State private var message: String?
    @State private var model = ""

    var body: some View {
        SettingsLead(text: "입력창 맨 앞에 . 을 치거나, 친 뒤 ⇥ 로 「AI 에게 묻기」 를 고르면 웹을 검색해 최신 정보로 답합니다.")
        SettingsSection(title: "OpenRouter 키",
                        footer: message ?? "키는 이 맥의 키체인에만 저장됩니다. 질문과 답은 OpenRouter 로 오가고 \(AppIdentity.name) 은 저장하지 않습니다.") {
            SettingsRow(title: hasSavedKey ? "저장되어 있습니다" : "아직 없습니다", detail: hasSavedKey ? "새 키를 넣으면 바뀝니다" : "openrouter.ai 에서 만든 키를 붙여 넣으세요") {
                if hasSavedKey {
                    RowButton("지우기", role: .destructive) {
                        KeyStore.delete()
                        hasSavedKey = false
                        message = "이 맥에서 키를 지웠습니다."
                    }
                }
            }
            FieldRow(placeholder: "sk-or-…", text: $draftKey, secure: true, monospaced: true,
                     button: ("저장", !draftKey.trimmingCharacters(in: .whitespaces).isEmpty, save), onSubmit: save)
        }
        SettingsSection(title: "모델", footer: "OpenRouter 의 모델 이름. 비우면 기본값(\(AIRequest.defaultModel))을 씁니다.") {
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
            message = "키를 저장하지 못했습니다."
            return
        }
        draftKey = ""
        hasSavedKey = true
        message = "저장했습니다."
    }

    private func saveModel() {
        let trimmed = model.trimmingCharacters(in: .whitespaces)
        settings.update { $0.aiModel = trimmed.isEmpty ? AIRequest.defaultModel : trimmed }
    }
}
