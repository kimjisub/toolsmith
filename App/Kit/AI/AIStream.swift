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
            return [.error(error["message"] as? String ?? localized("The AI stopped while answering."))]
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
    /// Written for the model, not shown to people, so it is not localized: the model answers in the question's language.
    public static let systemPrompt = """
        You are an assistant answering right inside a Mac launcher's prompt. Answer from web search results with up-to-date information. \
        Answer in the language of the question. Lead with the conclusion, keep it short, and add only the evidence that is needed. \
        Give an answer that can be used at once: no greetings, no questions back, no filler. Cite sources at the end of the sentence as [site name](address). \
        Do not guess what the search could not confirm; say that it could not be confirmed. \
        Do not use headings (#), tables or code blocks; write only sentences and short lists.
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
    public static func errorMessage(status: Int, body: Data, locale: Locale = .app) -> String {
        switch status {
        case 401: return localized("The OpenRouter key is not valid. Enter it again in Settings → AI Answers.", locale: locale)
        case 402: return localized("Your OpenRouter credits have run out.", locale: locale)
        case 429: return localized("Too many requests. Ask again in a moment.", locale: locale)
        default:
            if let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
               let error = json["error"] as? [String: Any], let message = error["message"] as? String, !message.isEmpty {
                return message
            }
            return localized("The AI could not answer (\(status)).", locale: locale)
        }
    }
}
