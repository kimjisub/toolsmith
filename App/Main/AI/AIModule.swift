import SwiftUI
import ToolsmithKit

/// AI 검색: the launcher's 「AI 에게 묻기」 row and the "." that switches to it.
@MainActor final class AIModule: AppModule {
    nonisolated static let descriptor = ModuleDescriptor(id: "ai", title: "AI 검색", summary: "입력창에서 웹 검색이 붙은 AI 답을 받습니다. 물을 때만 질문을 보냅니다",
                                             symbol: "sparkles", tint: .purple, requires: [LauncherModule.descriptor.id])
    var descriptor: ModuleDescriptor { Self.descriptor }
    private unowned let host: ModuleHost

    init(host: ModuleHost) { self.host = host }

    func settingsGroups(in environment: AppEnvironment) -> AnyView? { AnyView(AIPane(settings: environment.settings)) }
    func start() { host.model.allowsAI = true }
    func stop() { host.model.allowsAI = false }
}
