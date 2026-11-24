import AppKit
import Combine
import SwiftUI
import ToolsmithKit

/// The monitor in the menu bar panel: the dashboard is the panel's monitor screen; the details of
/// the row the pointer is on open to the panel's left, and the history of the block the pointer is
/// on within those details further left. The side windows are non-activating panels too, so
/// looking at the monitor does not take the user out of the app they are in.
@MainActor final class MonitorPanels {
    private let monitor: MonitorModel
    /// The menu bar panel's window while it shows the dashboard.
    private weak var host: NSWindow?
    private lazy var details = FloatingPanel()
    private lazy var history = FloatingPanel()
    private let selection = HistorySelection()
    private var historyTop: CGFloat = 0
    /// On screen: the dashboard row whose details are open, and the block whose history is open.
    private var rowRect: NSRect?
    private var blockRect: NSRect?
    /// Where the rows sit in the dashboard and the blocks in the details (SwiftUI space, top-left origin).
    private var rowFrames: [MonitorSection: CGRect] = [:]
    private var blockFrames: [HistoryTopic: CGRect] = [:]
    /// Since when the pointer has been off what keeps each level open (nil while it is on it).
    private var detailsLeftAt: Date?
    private var historyLeftAt: Date?
    /// Whether the pointer has been over the panel or a side window since the monitor opened. Until
    /// then (opened from a menu bar meter, pointer still in the menu bar) the details stay open.
    private var pointerEntered = false
    private var pointerTimer: Timer?
    /// How long the pointer may be off before a level closes: enough to move across the gap into it.
    private static let grace: TimeInterval = 0.3
    private var detailTop: CGFloat = 0
    private(set) var isShown = false

    init(monitor: MonitorModel, fan: FanController, charge: @escaping @MainActor () -> ChargeController?,
         openSettings: @escaping @MainActor (SettingsPane?) -> Void) {
        self.monitor = monitor
        let selection = self.selection
        // The windows belong to this object; their content builders must not hold it.
        details.makeContent = { [weak self] in
            DetailContainer(monitor: monitor, fan: fan, charge: charge(), selection: selection,
                            maxHeight: { self?.detailMaxHeight ?? 600 },
                            onChargeSettings: { openSettings(.battery) })
                .environment(\.historyFrame, { topic, frame in self?.blockFrames[topic] = frame })
        }
        details.onSizeChange = { [weak self] in self?.placeDetails() }
        history.makeContent = { HistoryPanelView(monitor: monitor, selection: selection) }
        history.onSizeChange = { [weak self] in self?.placeHistory() }
    }

    /// The dashboard, for the panel's monitor screen.
    func dashboard() -> AnyView {
        AnyView(DashboardView(monitor: monitor, onRowFrame: { [weak self] section, frame in self?.rowFrames[section] = frame }))
    }

    /// The dashboard came up in `window`: start reading every second and following the pointer.
    func attach(to window: NSWindow) {
        host = window
        guard !isShown else { return }
        isShown = true
        monitor.setOpen(true)
        details.attach()
        history.attach()
        pointerEntered = false
        startFollowingPointer()
    }

    /// The dashboard went away: close the side windows and go back to light readings.
    func detach() {
        guard isShown else { return }
        isShown = false
        hideDetails()
        pointerTimer?.invalidate()
        pointerTimer = nil
        // Closed windows keep no views: nothing redraws while the monitor is not on screen.
        details.detach()
        history.detach()
        monitor.setOpen(false)
        rowFrames = [:]
        host = nil
    }

    /// The side windows on screen; a click in them belongs to the panel.
    var sideWindows: [NSWindow] { [details, history].filter(\.isVisible) }

    /// Opens a section's details right away (a menu bar meter was clicked).
    func open(_ section: MonitorSection) {
        guard isShown else { return }
        showDetails(section, cardFrame: nil)
    }

    /// `cardFrame` is the card's frame in the panel (SwiftUI global coordinates, top-left origin).
    private func showDetails(_ section: MonitorSection, cardFrame: CGRect?) {
        guard let host else { return }
        if monitor.detail != section {
            hideHistory()
            blockFrames = [:]
        }
        monitor.showDetail(section)
        let top = cardFrame.map { host.frame.maxY - $0.minY + Space.m } ?? host.frame.maxY
        detailTop = top
        rowRect = cardFrame.map { Self.screenRect($0, in: host) }
        detailsLeftAt = nil
        placeDetails()
        details.orderFrontRegardless()
    }

    /// `blockFrame` is the block's frame in the details (SwiftUI global coordinates, top-left origin).
    func showHistory(_ topic: HistoryTopic, blockFrame: CGRect) {
        guard isShown else { return }
        selection.topic = topic
        historyTop = details.frame.maxY - blockFrame.minY
        blockRect = Self.screenRect(blockFrame, in: details)
        historyLeftAt = nil
        placeHistory()
        history.orderFrontRegardless()
    }

    private func hideHistory() {
        selection.topic = nil
        blockRect = nil
        historyLeftAt = nil
        history.orderOut(nil)
    }

    private func hideDetails() {
        hideHistory()
        rowRect = nil
        detailsLeftAt = nil
        details.orderOut(nil)
        monitor.showDetail(nil)
    }

    /// A frame in a window's SwiftUI space (top-left origin) on screen.
    private static func screenRect(_ frame: CGRect, in window: NSWindow) -> NSRect {
        NSRect(x: window.frame.minX + frame.minX, y: window.frame.maxY - frame.maxY, width: frame.width, height: frame.height)
    }

    /// Each level stays open while the pointer is on what opened it (the row, the block) or on the
    /// level itself or a deeper one, and closes a moment after it leaves.
    private func startFollowingPointer() {
        pointerTimer?.invalidate()
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.followPointer() } }
        RunLoop.main.add(timer, forMode: .common)
        pointerTimer = timer
    }

    private func followPointer() {
        guard isShown, let host else { return }
        #if TOOLSMITH_DEV
        // Development aid: a history opened with --history stays open while the windows are drawn into pictures.
        if CommandLine.arguments.contains("--history") { return }
        #endif
        let pointer = NSEvent.mouseLocation
        let inHistory = history.isVisible && history.frame.contains(pointer)
        let inDetails = details.isVisible && details.frame.contains(pointer)
        let inDashboard = host.frame.contains(pointer)
        if inHistory || inDetails || inDashboard { pointerEntered = true }
        let now = Date()

        // Open what the pointer is on: a row's details, a block's history.
        if inDashboard, let (section, frame) = rowFrames.first(where: { Self.screenRect($0.value, in: host).contains(pointer) }),
           monitor.detail != section || !details.isVisible {
            showDetails(section, cardFrame: frame)
        }
        if inDetails, let (topic, frame) = blockFrames.first(where: { Self.screenRect($0.value, in: details).contains(pointer) }),
           selection.topic != topic {
            showHistory(topic, blockFrame: frame)
        }

        if selection.topic != nil {
            let keep = inHistory || (blockRect?.contains(pointer) ?? false)
            if keep { historyLeftAt = nil } else if let left = historyLeftAt {
                if now.timeIntervalSince(left) > Self.grace { hideHistory() }
            } else {
                historyLeftAt = now
            }
        }
        if monitor.detail != nil {
            let onRow = rowRect?.contains(pointer) ?? false
            let keep = inHistory || inDetails || onRow || !pointerEntered
            if keep { detailsLeftAt = nil } else if let left = detailsLeftAt {
                if now.timeIntervalSince(left) > Self.grace { hideDetails() }
            } else {
                detailsLeftAt = now
            }
        }
    }

    /// Left of the details, its top level with the block, kept on screen.
    private func placeHistory() {
        guard isShown, selection.topic != nil, let visible = (host?.screen ?? NSScreen.main)?.visibleFrame else { return }
        let size = history.fittingSize
        let top = min(max(historyTop, visible.minY + Space.xs + size.height), visible.maxY - Space.xs)
        let x = max(details.frame.minX - size.width - Space.s, visible.minX + Space.xs)
        history.setFrame(NSRect(x: x, y: top - size.height, width: size.width, height: size.height), display: true)
    }

    private var detailMaxHeight: CGFloat {
        let screen = host?.screen ?? NSScreen.main
        return (screen?.visibleFrame.height ?? 800) - Space.s
    }

    /// Left of the panel, its top level with the card, moved up as far as needed to stay on screen.
    private func placeDetails() {
        guard isShown, let host, let visible = (host.screen ?? NSScreen.main)?.visibleFrame else { return }
        let size = details.fittingSize
        let top = min(max(detailTop, visible.minY + Space.xs + size.height), visible.maxY - Space.xs)
        details.setFrame(NSRect(x: host.frame.minX - size.width - Space.s, y: top - size.height, width: size.width, height: size.height), display: true)
    }
}

/// The details of whichever section the model says is showing, scrolled when taller than the screen.
private struct DetailContainer: View {
    @ObservedObject var monitor: MonitorModel
    @ObservedObject var fan: FanController
    let charge: ChargeController?
    let selection: HistorySelection
    let maxHeight: () -> CGFloat
    let onChargeSettings: () -> Void
    @State private var contentHeight: CGFloat = 400

    var body: some View {
        ScrollView {
            content
                .padding(Space.m)
                .frame(width: MonitorStyle.width)
                .foregroundStyle(Ink.primary)
                .background(GeometryReader { proxy in
                    Color.clear.onAppear { contentHeight = proxy.size.height }
                        .onChange(of: proxy.size.height) { _, height in contentHeight = height }
                })
        }
        .scrollIndicators(.never)
        .frame(width: MonitorStyle.width, height: min(contentHeight, maxHeight()))
    }

    @ViewBuilder private var content: some View {
        switch monitor.detail {
        case .cpu: CPUDetailView(monitor: monitor, processes: monitor.processes, selection: selection)
        case .sensors: SensorsDetailView(monitor: monitor, fan: fan, selection: selection)
        case .memory: MemoryDetailView(monitor: monitor, processes: monitor.processes, selection: selection)
        case .disk: DiskDetailView(monitor: monitor, selection: selection)
        case .network: NetworkDetailView(monitor: monitor, processes: monitor.processes, publicAddress: monitor.publicAddress, selection: selection)
        case .battery: BatteryDetailView(monitor: monitor, processes: monitor.processes, charge: charge, selection: selection, onChargeSettings: onChargeSettings)
        case nil: EmptyView()
        }
    }
}

