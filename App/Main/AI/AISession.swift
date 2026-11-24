import Combine
import Foundation
import ToolsmithKit

/// One question and its answer, as shown in the launcher.
struct AITurn: Identifiable, Equatable {
    let id = UUID()
    let question: String
    var answer = ""
    var citations: [Citation] = []
    var error: String?
    var isStreaming = true
}

/// The conversation in the open launcher. It lives until the launcher closes; nothing is kept after.
@MainActor final class AISession: ObservableObject {
    @Published private(set) var turns: [AITurn] = []
    private var task: Task<Void, Never>?
    var model: () -> String = { AIRequest.defaultModel }

    var isStreaming: Bool { turns.last?.isStreaming == true }
    var isEmpty: Bool { turns.isEmpty }
    var lastAnswer: String? { turns.last(where: { !$0.answer.isEmpty })?.answer }

    func ask(_ question: String, key: String) {
        stop()
        // Earlier questions and answers go along, so a follow-up is understood.
        var history: [AIMessage] = []
        for turn in turns where turn.error == nil && !turn.answer.isEmpty {
            history.append(AIMessage(role: .user, text: turn.question))
            history.append(AIMessage(role: .assistant, text: turn.answer))
        }
        history.append(AIMessage(role: .user, text: question))
        turns.append(AITurn(question: question))
        // The task finds its turn by id: the list may be cleared or changed while the answer streams.
        let id = turns[turns.count - 1].id

        var request = URLRequest(url: AIRequest.endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = AIRequest.body(model: model(), system: AIRequest.systemPrompt, messages: history)

        task = Task { [weak self] in
            do {
                let (bytes, response) = try await URLSession.shared.bytes(for: request)
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                guard status == 200 else {
                    var body = Data()
                    for try await byte in bytes { body.append(byte); if body.count > 65_536 { break } }
                    self?.finish(id, error: AIRequest.errorMessage(status: status, body: body))
                    return
                }
                var parser = AIStreamParser()
                // Tokens arrive far faster than the view needs: they are shown in small batches,
                // so the answer is not laid out again for every one.
                var waiting = ""
                var shownAt = ContinuousClock.now
                @MainActor func show() {
                    guard !waiting.isEmpty else { return }
                    let text = waiting
                    waiting = ""
                    shownAt = .now
                    self?.update(id) { $0.answer += text }
                }
                defer { show() }
                for try await line in bytes.lines {
                    for event in parser.feed(line) {
                        guard let self else { return }
                        switch event {
                        case .text(let text):
                            waiting += text
                            if ContinuousClock.now - shownAt > .milliseconds(60) { show() }
                        case .citations(let found):
                            show()
                            self.update(id) { $0.citations = Citation.merge($0.citations, found) }
                        case .error(let message):
                            show()
                            self.finish(id, error: message)
                            return
                        case .done:
                            show()
                            self.finish(id, error: nil)
                            return
                        }
                    }
                }
                show()
                self?.finish(id, error: nil)
            } catch is CancellationError {
                self?.finish(id, error: nil)
            } catch let error as URLError where error.code == .cancelled {
                self?.finish(id, error: nil)
            } catch {
                self?.finish(id, error: "AI 에 연결하지 못했습니다: \(error.localizedDescription)")
            }
        }
    }

    private func update(_ id: UUID, _ change: (inout AITurn) -> Void) {
        guard !Task.isCancelled, let index = turns.firstIndex(where: { $0.id == id }), turns[index].isStreaming else { return }
        change(&turns[index])
    }

    private func finish(_ id: UUID, error: String?) {
        guard let index = turns.firstIndex(where: { $0.id == id }), turns[index].isStreaming else { return }
        turns[index].isStreaming = false
        if let error {
            turns[index].error = error
        } else if turns[index].answer.isEmpty {
            turns[index].error = "답이 오지 않았습니다."
        } else if turns[index].citations.isEmpty {
            // No citation list came: the links written in the answer are the sources.
            turns[index].citations = Citation.fromMarkdownLinks(in: turns[index].answer)
        }
    }

    /// Stops an answer in mid-flow, keeping what has arrived.
    func stop() {
        task?.cancel()
        task = nil
        if let last = turns.indices.last, turns[last].isStreaming {
            turns[last].isStreaming = false
            if turns[last].answer.isEmpty { turns[last].error = "멈췄습니다." }
        }
    }

    func clear() {
        stop()
        turns = []
    }

    /// Development aid: a finished answer to look at without calling the service.
    func loadDemo() {
        var turn = AITurn(question: "오늘 원달러 환율")
        turn.answer = "오늘 원/달러 환율은 **1,382.5원**입니다 ([investing.com](https://investing.com/currencies/usd-krw)). 전일보다 3.2원 올랐고, 장중 1,379원에서 1,385원 사이에서 움직였습니다 ([한국은행](https://www.bok.or.kr))."
        turn.citations = Citation.fromMarkdownLinks(in: turn.answer)
        turn.isStreaming = false
        turns = [turn]
    }
}
