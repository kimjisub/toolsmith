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
                let demo = Snippet(id: UUID(), name: "First hello",
                                   body: "Hi {name}, this is {my name:Alex}.\nHere are the {topic:meeting} notes from {company} you asked about last time.",
                                   createdAt: Date(), updatedAt: Date())
                self.host.model.beginFill(SnippetFill(snippet: demo, returnsToList: true))
                self.host.model.setFillValue("Sa", at: 0)
            }
            if arguments.contains("--snippet-search-demo") {
                // Development aid: the snippet search over made-up snippets (in a temporary file).
                let snippets = self
                for (name, body) in [("First hello", "Hi {name}, this is {my name:Alex}."),
                                     ("Meeting schedule", "Hi {name}, here is the schedule for our meeting."),
                                     ("Thanks for replying", "Thank you for getting back to me."),
                                     ("Request for documents", "Could you send the review documents by {deadline}?")] {
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
