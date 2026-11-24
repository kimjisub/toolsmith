import SwiftUI
import ToolsmithKit

/// AI answers: the launcher's "Ask AI" row and the "." that switches to it.
@MainActor final class AIModule: AppModule {
    nonisolated static let descriptor = ModuleDescriptor(id: "ai", title: String(localized: "AI Answers"), summary: String(localized: "Get AI answers backed by a web search in the launcher. Questions are sent only when you ask"),
                                             symbol: "sparkles", tint: .purple, requires: [LauncherModule.descriptor.id])
    var descriptor: ModuleDescriptor { Self.descriptor }
    private unowned let host: ModuleHost

    init(host: ModuleHost) { self.host = host }

    func settingsGroups(in environment: AppEnvironment) -> AnyView? { AnyView(AIPane(settings: environment.settings)) }
    func start() { host.model.allowsAI = true }
    func stop() { host.model.allowsAI = false }
}
