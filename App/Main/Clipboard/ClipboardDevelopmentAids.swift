import Foundation
import ToolsmithKit

#if TOOLSMITH_DEV
extension ClipboardModule {
    /// Development flags this module answers (see CLAUDE.md, 빌드와 확인).
    func runDevelopmentAid(_ arguments: [String]) {
        if arguments.contains("--clipboard-demo") { recordDemoItems() }
        if arguments.contains("--show-shelf") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { self.shelf?.show() }
        }
    }

    /// Development aid: made-up copies in the app's language, for screenshots without the user's own history.
    private func recordDemoItems() {
        guard let store else { return }
        let korean = Locale.app.language.languageCode == .korean
        let samples: [(ClipKind, String, String, String, Double)] = korean ? [
            (.text, "회의는 목요일 오후 3시로 옮겼습니다. 자료는 공유 폴더에 올려 두었어요.", "com.apple.mail", "Mail", 2),
            (.link, "https://github.com/kimjisub/toolsmith", "com.apple.Safari", "Safari", 9),
            (.text, "let total = items.reduce(0) { $0 + $1.price }", "com.apple.dt.Xcode", "Xcode", 25),
            (.text, "서울특별시 중구 세종대로 110", "com.apple.Notes", "메모", 70),
            (.link, "https://developer.apple.com/design/human-interface-guidelines", "com.apple.Safari", "Safari", 180),
            (.text, "다음 주 발표 순서: 소개, 데모, 질의응답", "com.apple.Notes", "메모", 400),
        ] : [
            (.text, "The meeting moved to Thursday at 3 PM. The slides are in the shared folder.", "com.apple.mail", "Mail", 2),
            (.link, "https://github.com/kimjisub/toolsmith", "com.apple.Safari", "Safari", 9),
            (.text, "let total = items.reduce(0) { $0 + $1.price }", "com.apple.dt.Xcode", "Xcode", 25),
            (.text, "1 Infinite Loop, Cupertino, CA 95014", "com.apple.Notes", "Notes", 70),
            (.link, "https://developer.apple.com/design/human-interface-guidelines", "com.apple.Safari", "Safari", 180),
            (.text, "Next week's talk: intro, demo, questions", "com.apple.Notes", "Notes", 400),
        ]
        for (kind, text, bundleID, name, minutesAgo) in samples.reversed() {
            let draft = ClipDraft(kind: kind, text: text, data: nil, fileURLs: [], sourceBundleID: bundleID, sourceName: name, width: nil, height: nil)
            _ = try? store.record(draft, at: Date().addingTimeInterval(-minutesAgo * 60))
        }
        changed()
    }
}
#endif
