import Foundation

#if TOOLSMITH_DEV
extension ClipboardModule {
    /// Development flags this module answers (see CLAUDE.md, 빌드와 확인).
    func runDevelopmentAid(_ arguments: [String]) {
        if arguments.contains("--show-shelf") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { self.shelf?.show() }
        }
    }
}
#endif
