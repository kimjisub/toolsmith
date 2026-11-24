import Combine
import SwiftUI
import ToolsmithKit

/// What the pane shows, read from the store in one go.
struct ScreenTimeReport {
    var apps: [AppUsage] = []
    var hourly = [Double](repeating: 0, count: 24)
    /// The last seven days, oldest first; the last is today.
    var week: [Double] = []

    var total: Double { apps.reduce(0) { $0 + $1.seconds } }
    /// The six days before today, each up to this time of day, oldest first.
    var earlierByThisTime: [Double] = []
    var insights: [String] { ScreenTimeInsights.lines(apps: apps, hourly: hourly, previousDays: earlierByThisTime, byThisTime: true) }

    init() {}

    init(store: ScreenTimeStore, now: Date = Date()) {
        apps = store.apps(on: now)
        hourly = store.hourly(on: now)
        week = store.dailyTotals(endingOn: now, days: 7)
        earlierByThisTime = store.totalsByThisTime(before: now, days: 6)
    }
}

struct ScreenTimePane: View {
    let screenTime: ScreenTimeModule
    @State private var report = ScreenTimeReport()
    @State private var confirmingClear = false
    private let timer = Timer.publish(every: 15, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xxl) {
            SettingsLead(text: String(localized: "Time isn’t counted after 5 minutes without input, or while the screen is locked or off. During a video call that uses the microphone or camera, it counts even without input."))
            ScreenTimeContent(report: report)
            SettingsSection(title: String(localized: "History"), footer: String(localized: "To stop recording, turn off Screen Time in Settings → Features. What’s already recorded stays.")) {
                SettingsRow(title: String(localized: "Clear history"), detail: String(localized: "Deletes all screen time recorded so far")) {
                    RowButton(String(localized: "Clear All…"), role: .destructive) { confirmingClear = true }
                }
            }
        }
        .onAppear(perform: refresh)
        .onReceive(timer) { _ in refresh() }
        .confirmationDialog("Clear all screen time history?", isPresented: $confirmingClear) {
            Button("Clear All", role: .destructive) { screenTime.store?.clearAll(); refresh() }
            Button("Cancel", role: .cancel) {}
        } message: { Text("You can’t undo this.") }
    }

    private func refresh() {
        screenTime.flush()
        if let store = screenTime.store { report = ScreenTimeReport(store: store) }
    }
}

/// The report itself, separate from the controls so it can be drawn on its own.
struct ScreenTimeContent: View {
    let report: ScreenTimeReport

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            VStack(alignment: .leading, spacing: Space.xs) {
                Text("Screen time today").font(.role(.secondary)).foregroundStyle(Ink.tertiary)
                Text(report.total > 0 ? DurationText.text(report.total) : String(localized: "0 min")).font(.role(.figure, weight: .semibold))
            }
            card {
                ForEach(report.insights, id: \.self) { line in
                    HStack(alignment: .top, spacing: Space.s) {
                        Circle().fill(Brand.lavender).frame(width: 5, height: 5).padding(.top, Space.s)
                        Text(line).font(.role(.body)).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            card {
                caption(String(localized: "By hour"))
                Bars(values: report.hourly, labels: [0, 6, 12, 18].map { ($0, String(localized: "\($0):00")) }, highlightLast: false).frame(height: 70)
            }
            card {
                caption(String(localized: "By app"))
                if report.apps.isEmpty {
                    Text("Nothing recorded yet.").font(.role(.secondary)).foregroundStyle(Ink.tertiary)
                }
                let top = report.apps.first?.seconds ?? 1
                ForEach(report.apps.prefix(8)) { app in
                    HStack(spacing: Space.m) {
                        if let icon = AppIconCache.icon(bundleID: app.bundleID) {
                            Image(nsImage: icon).resizable().frame(width: 18, height: 18)
                        } else {
                            Color.clear.frame(width: 18, height: 18)
                        }
                        Text(app.name).font(.role(.body)).lineLimit(1).frame(width: 130, alignment: .leading)
                        GeometryReader { proxy in
                            Capsule().fill(Brand.gradient).frame(width: max(3, proxy.size.width * app.seconds / top))
                                .frame(maxHeight: .infinity, alignment: .center)
                        }
                        .frame(height: 6)
                        Text(DurationText.text(app.seconds)).font(.role(.secondary, design: .monospaced)).foregroundStyle(Ink.tertiary)
                            .frame(width: 86, alignment: .trailing)
                    }
                }
                if report.apps.count > 8 {
                    Text("\(report.apps.count - 8) more").font(.role(.secondary)).foregroundStyle(Ink.tertiary)
                }
            }
            card {
                caption(String(localized: "Last 7 days"))
                Bars(values: report.week, labels: report.week.count > 1 ? [(0, String(localized: "\(report.week.count - 1) days ago")), (report.week.count - 1, String(localized: "Today"))] : [], highlightLast: true).frame(height: 70)
            }
        }
        .foregroundStyle(Ink.primary)
    }

    private func caption(_ text: String) -> some View {
        Text(text).font(.role(.secondary)).foregroundStyle(Ink.tertiary)
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Space.s) { content() }
            .padding(Space.l)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Fill.card, in: RoundedRectangle(cornerRadius: Radius.m, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Radius.m, style: .continuous).strokeBorder(Line.subtle, lineWidth: 1))
    }
}

/// Bars for a short series (the hours of a day, the days of a week), with a few labels underneath.
private struct Bars: View {
    let values: [Double]
    /// Labels with the index of the bar each sits under.
    let labels: [(index: Int, text: String)]
    let highlightLast: Bool

    var body: some View {
        let top = max(values.max() ?? 0, 1)
        VStack(spacing: Space.xs) {
            HStack(alignment: .bottom, spacing: Space.xs) {
                ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                    GeometryReader { proxy in
                        RoundedRectangle(cornerRadius: Radius.xs)
                            .fill(highlightLast && index == values.count - 1 ? Brand.peach : Tint.strong(Brand.lavender))
                            .frame(height: value > 0 ? max(2, proxy.size.height * value / top) : 1)
                            .opacity(value > 0 ? 1 : 0.25)
                            .frame(maxHeight: .infinity, alignment: .bottom)
                    }
                    .help(DurationText.text(value))
                }
            }
            GeometryReader { proxy in
                let step = values.isEmpty ? 0 : proxy.size.width / CGFloat(values.count)
                ForEach(labels, id: \.index) { label in
                    let index = label.index
                    Text(label.text).font(.role(.caption)).foregroundStyle(Ink.tertiary).fixedSize()
                        .position(x: min(max(step * (CGFloat(index) + 0.5), 14), proxy.size.width - 14), y: 6)
                }
            }
            .frame(height: 12)
        }
    }
}
