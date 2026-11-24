import AppKit
import SwiftUI
import ToolsmithKit

/// The questions asked and the answers, under the launcher's field.
struct AIAnswerView: View {
    @ObservedObject var session: AISession
    let maxHeight: CGFloat

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: Space.l) {
                    ForEach(session.turns) { turn in
                        turnView(turn).id(turn.id)
                    }
                    Color.clear.frame(height: 1).id("end")
                }
                .padding(.horizontal, Space.xl)
                .padding(.vertical, Space.l)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.never)
            .frame(maxHeight: maxHeight)
            .fixedSize(horizontal: false, vertical: true)
            // Follow the answer as it grows.
            .onChange(of: session.turns.last?.answer) { _, _ in proxy.scrollTo("end", anchor: .bottom) }
            .onChange(of: session.turns.count) { _, _ in proxy.scrollTo("end", anchor: .bottom) }
        }
    }

    /// Opens a source without bringing the browser forward: the launcher closes when it loses
    /// focus, and the answer with the other sources would go with it.
    private static func openBehind(_ url: URL) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        NSWorkspace.shared.open(url, configuration: configuration)
    }

    private func turnView(_ turn: AITurn) -> some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Text(turn.question).font(.role(.secondary)).foregroundStyle(Ink.tertiary)
            if !turn.answer.isEmpty {
                Text(Self.formatted(turn.answer))
                    .font(.role(.emphasis))
                    .foregroundStyle(Ink.primary)
                    .lineSpacing(4)
                    .tint(Brand.lavender)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .environment(\.openURL, OpenURLAction { url in
                        guard WebLink.isWeb(url) else { return .discarded }
                        Self.openBehind(url)
                        return .handled
                    })
            }
            if turn.isStreaming {
                HStack(spacing: Space.s) {
                    Spinner()
                    Text(turn.answer.isEmpty ? "Searching the web…" : "Answering…").font(.role(.secondary)).foregroundStyle(Ink.tertiary)
                }
            }
            if let error = turn.error {
                HStack(alignment: .top, spacing: Space.s) {
                    Image(systemName: "exclamationmark.circle").foregroundStyle(Status.warning)
                    Text(error).font(.role(.body)).foregroundStyle(Status.warning).textSelection(.enabled)
                }
            }
            if !turn.citations.isEmpty {
                FlowLayout(spacing: Space.s) {
                    ForEach(Array(turn.citations.enumerated()), id: \.offset) { index, citation in
                        Button {
                            if let url = WebLink.url(citation.url) { Self.openBehind(url) }
                        } label: {
                            HStack(spacing: Space.xs) {
                                Text(verbatim: "\(index + 1)").font(.role(.caption, weight: .semibold, design: .monospaced)).foregroundStyle(Ink.tertiary)
                                Text(citation.title).font(.role(.detail)).lineLimit(1)
                            }
                            .foregroundStyle(Ink.secondary)
                            .padding(.horizontal, Space.s)
                            .padding(.vertical, Space.xs)
                            .frame(maxWidth: 220)
                            .background(Fill.control, in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .help(citation.url)
                    }
                }
            }
        }
    }

    /// Inline Markdown (bold, links) with the line breaks kept as written.
    static func formatted(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
    }
}

/// Lays chips out left to right, wrapping to the next line.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(in: proposal.width ?? .infinity, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let placement = arrange(in: bounds.width, subviews: subviews)
        for (index, point) in placement.points.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + point.x, y: bounds.minY + point.y), proposal: .unspecified)
        }
    }

    private func arrange(in width: CGFloat, subviews: Subviews) -> (size: CGSize, points: [CGPoint]) {
        var points: [CGPoint] = []
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, widest: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            points.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            widest = max(widest, x - spacing)
        }
        return (CGSize(width: widest, height: y + rowHeight), points)
    }
}
