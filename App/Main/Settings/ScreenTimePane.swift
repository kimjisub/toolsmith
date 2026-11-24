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
            SettingsLead(text: "5분 넘게 손을 대지 않거나 화면이 잠기거나 꺼지면 세지 않습니다. 마이크나 카메라를 쓰는 화상 회의 중이면 손을 대지 않아도 셉니다.")
            ScreenTimeContent(report: report)
            SettingsSection(title: "기록", footer: "기록을 멈추려면 설정의 「기능」 에서 사용 시간을 끕니다. 이미 쌓인 기록은 남습니다.") {
                SettingsRow(title: "기록 지우기", detail: "지금까지의 사용 시간을 모두 지웁니다") {
                    RowButton("모두 지우기…", role: .destructive) { confirmingClear = true }
                }
            }
        }
        .onAppear(perform: refresh)
        .onReceive(timer) { _ in refresh() }
        .confirmationDialog("사용 시간 기록을 모두 지울까요?", isPresented: $confirmingClear) {
            Button("모두 지우기", role: .destructive) { screenTime.store?.clearAll(); refresh() }
            Button("취소", role: .cancel) {}
        } message: { Text("지운 기록은 되돌릴 수 없습니다.") }
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
                Text("오늘 사용 시간").font(.role(.secondary)).foregroundStyle(Ink.tertiary)
                Text(report.total > 0 ? DurationText.text(report.total) : "0분").font(.role(.figure, weight: .semibold))
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
                caption("시간대별")
                Bars(values: report.hourly, labels: [(0, "0시"), (6, "6시"), (12, "12시"), (18, "18시")], highlightLast: false).frame(height: 70)
            }
            card {
                caption("앱별")
                if report.apps.isEmpty {
                    Text("아직 기록이 없습니다.").font(.role(.secondary)).foregroundStyle(Ink.tertiary)
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
                    Text("외 \(report.apps.count - 8)개").font(.role(.secondary)).foregroundStyle(Ink.tertiary)
                }
            }
            card {
                caption("최근 7일")
                Bars(values: report.week, labels: report.week.count > 1 ? [(0, "\(report.week.count - 1)일 전"), (report.week.count - 1, "오늘")] : [], highlightLast: true).frame(height: 70)
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
