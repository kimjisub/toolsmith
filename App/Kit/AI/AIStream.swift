import Foundation

/// A source the answer rests on.
/// Which links from an answer may be opened. The answer is written from web pages, which can carry
/// instructions; a link to a file or another app's scheme could do more than show a page.
public enum WebLink {
    public static func isWeb(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else { return false }
        return url.host?.isEmpty == false
    }

    public static func url(_ string: String) -> URL? {
        URL(string: string).flatMap { isWeb($0) ? $0 : nil }
    }
}

public struct Citation: Equatable, Hashable, Sendable {
    public let title: String
    public let url: String

    public init(title: String, url: String) {
        self.title = title
        self.url = url
    }

    /// `existing` followed by the new ones, each address once.
    public static func merge(_ existing: [Citation], _ new: [Citation]) -> [Citation] {
        var seen = Set(existing.map(\.url))
        return existing + new.filter { seen.insert($0.url).inserted }
    }

    /// Web links written in the answer as `[name](https://…)`, in order, each address once.
    /// Used when the service sent no citation list of its own.
    public static func fromMarkdownLinks(in text: String) -> [Citation] {
        guard let pattern = try? NSRegularExpression(pattern: #"\[([^\]]+)\]\((https?://[^)\s]+)\)"#) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        let found = pattern.matches(in: text, range: range).compactMap { match -> Citation? in
            guard let title = Range(match.range(at: 1), in: text), let url = Range(match.range(at: 2), in: text) else { return nil }
            return Citation(title: String(text[title]), url: String(text[url]))
        }
        return merge([], found)
    }

    static func host(of url: String) -> String {
        let host = URLComponents(string: url)?.host ?? url
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }
}

public enum AIStreamEvent: Equatable {
    case text(String)
    case citations([Citation])
    case error(String)
    case done
}

/// Reads the streamed answer (server-sent events) one line at a time.
public struct AIStreamParser {
    public init() {}

    public mutating func feed(_ line: String) -> [AIStreamEvent] {
        // Lines that start with ":" are keep-alive comments; anything but "data:" carries nothing for us.
        guard line.hasPrefix("data:") else { return [] }
        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
        if payload == "[DONE]" { return [.done] }
        guard let json = try? JSONSerialization.jsonObject(with: Data(payload.utf8)) as? [String: Any] else { return [] }

        if let error = json["error"] as? [String: Any] {
            return [.error(error["message"] as? String ?? "AI 가 답하다가 멈췄습니다.")]
        }
        var events: [AIStreamEvent] = []
        for choice in json["choices"] as? [[String: Any]] ?? [] {
            // Streaming chunks use "delta"; some providers send the closing citations under "message".
            for key in ["delta", "message"] {
                guard let part = choice[key] as? [String: Any] else { continue }
                if let content = part["content"] as? String, !content.isEmpty { events.append(.text(content)) }
                let citations = (part["annotations"] as? [[String: Any]] ?? []).compactMap { annotation -> Citation? in
                    guard annotation["type"] as? String == "url_citation",
                          let detail = annotation["url_citation"] as? [String: Any],
                          let url = detail["url"] as? String, !url.isEmpty else { return nil }
                    let title = (detail["title"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? Citation.host(of: url)
                    return Citation(title: title, url: url)
                }
                if !citations.isEmpty { events.append(.citations(citations)) }
            }
        }
        return events
    }
}

public struct AIMessage: Equatable, Sendable {
    public enum Role: String, Sendable { case user, assistant }
    public let role: Role
    public let text: String

    public init(role: Role, text: String) {
        self.role = role
        self.text = text
    }
}

/// The request to OpenRouter for an answer grounded in a web search.
public enum AIRequest {
    public static let endpoint = URL(string: "https://openrouter.ai/api/v1/chat/completions")!
    public static let defaultModel = "anthropic/claude-haiku-5.5"

    /// How the answer should read. Asked from a launcher: short, usable at once, sources named.
    public static let systemPrompt = """
        너는 맥 런처 입력창에서 바로 답하는 도우미다. 웹 검색 결과에 근거해 최신 정보로 답한다. \
        질문한 언어로 답하고, 한국어 질문에는 한국어로 답한다. 결론부터 짧게 쓰고 꼭 필요한 근거만 붙인다. \
        인사, 되묻기, 군더더기 없이 바로 쓸 수 있는 답을 준다. 출처는 문장 끝에 [사이트이름](주소) 형식으로 단다. \
        검색으로 확인하지 못한 것은 추측하지 말고 확인하지 못했다고 말한다. \
        제목(#), 표, 코드 블록은 쓰지 않고 문장과 짧은 목록으로만 쓴다.
        """

    public static func body(model: String, system: String, messages: [AIMessage]) -> Data {
        let payload: [String: Any] = [
            "model": model,
            "stream": true,
            // The web plugin runs a search and hands the results to the model.
            "plugins": [["id": "web", "max_results": 5]],
            "messages": [["role": "system", "content": system]] + messages.map { ["role": $0.role.rawValue, "content": $0.text] },
        ]
        return (try? JSONSerialization.data(withJSONObject: payload)) ?? Data()
    }

    /// One line a person can act on, for a request that failed before any answer came.
    public static func errorMessage(status: Int, body: Data) -> String {
        switch status {
        case 401: return "OpenRouter 키가 맞지 않습니다. 설정의 AI 검색에서 다시 넣어 주세요."
        case 402: return "OpenRouter 크레딧이 부족합니다."
        case 429: return "요청이 너무 많습니다. 잠시 뒤에 다시 물어 주세요."
        default:
            if let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
               let error = json["error"] as? [String: Any], let message = error["message"] as? String, !message.isEmpty {
                return message
            }
            return "AI 가 답하지 못했습니다 (\(status))."
        }
    }
}
