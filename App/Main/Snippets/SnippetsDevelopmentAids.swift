import Foundation
import ToolsmithKit

#if TOOLSMITH_DEV
extension SnippetsModule {
    /// Development flags this module answers (see CLAUDE.md, 빌드와 확인).
    func runDevelopmentAid(_ arguments: [String]) {
        // With --snapshot-settings the snippets page is drawn with a new snippet open.
        if arguments.contains("--snapshot-settings"), arguments.contains("--snippet-demo") { draftRequested = true }
        guard arguments.contains("--show-launcher"), arguments.contains("--snippet-demo") || arguments.contains("--snippet-search-demo") else { return }
        // Right after the shell's own --show-launcher has opened the launcher.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.05) {
            self.host.panel.show()
            if arguments.contains("--snippet-demo") {
                // Development aid: the fill screen of a made-up snippet (nothing is saved).
                let demo = Snippet(id: UUID(), name: "첫 연락 인사",
                                   body: "{이름}님 안녕하세요, {내 이름:김지섭}입니다.\n{회사}에서 지난번 말씀하신 {주제:회의} 자료를 보내 드립니다.",
                                   createdAt: Date(), updatedAt: Date())
                self.host.model.beginFill(SnippetFill(snippet: demo, returnsToList: true))
                self.host.model.setFillValue("김", at: 0)
            }
            if arguments.contains("--snippet-search-demo") {
                // Development aid: the snippet search over made-up snippets (in a temporary file).
                let snippets = self
                for (name, body) in [("첫 연락 인사", "{이름}님 안녕하세요, {내 이름:김지섭}입니다."),
                                     ("회의 일정 안내", "{이름}님, 회의 일정을 안내드립니다."),
                                     ("연락 감사 인사", "답변 주셔서 감사합니다."),
                                     ("자료 요청", "검토 자료를 {마감} 까지 부탁드립니다.")] {
                    _ = snippets.store.add(name: name, body: body)
                }
                snippets.snippetsChanged()
                self.host.model.enterSnippetSearch(returnsToList: false)
                if let index = arguments.firstIndex(of: "--query"), index + 1 < arguments.count {
                    self.host.model.query = arguments[index + 1]
                }
            }
        }
    }
}
#endif
