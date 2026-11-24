import AppKit
import SwiftUI
import ToolsmithKit

/// Sizes and colors of the mixer. Every line is one row of a table whose columns line up under the
/// headers: name, volume, boost, device, effects.
enum MixerStyle {
    // Column widths on the 4 pt grid; the screen is exactly as wide as a row.
    static let nameWidth: CGFloat = 152
    static let volumeWidth: CGFloat = 200
    static let boostWidth: CGFloat = 36
    static let deviceWidth: CGFloat = 180
    static let fxWidth: CGFloat = 28
    static let columnGap = Space.s
    static let rowInset = Space.s
    static let screenInset = Space.m
    static let width: CGFloat = nameWidth + volumeWidth + boostWidth + deviceWidth + fxWidth + columnGap * 4 + rowInset * 2 + screenInset * 2
    static let rowHeight: CGFloat = 40
    static let listMaxHeight: CGFloat = 520

    static let accent = Brand.accent
    static let muted = Status.danger
    static let quiet = Ink.tertiary
    static let control = Fill.control
    static let expanded = Tint.wash(Brand.accent)
}

/// What the mixer remembers between openings: which groups are folded.
final class MixerViewState: ObservableObject {
    private static let defaults = UserDefaults.standard
    @Published var systemCollapsed = defaults.bool(forKey: "audio.systemCollapsed") { didSet { Self.defaults.set(systemCollapsed, forKey: "audio.systemCollapsed") } }
    @Published var appsCollapsed = defaults.bool(forKey: "audio.appsCollapsed") { didSet { Self.defaults.set(appsCollapsed, forKey: "audio.appsCollapsed") } }
}

/// A row that is open: its effects and actions are shown under it.
private enum Expanded: Hashable {
    case system(DeviceRole)
    case app(String)
}

/// The sound screen of the menu bar panel: the Mac's three devices in one rounded group, the apps in
/// another, then favorites and Quick Configs. A row's chevron opens its effects as cards underneath,
/// as SoundSource does. The panel around it draws the title, the pin and the way to the settings.
struct MixerView: View {
    @ObservedObject var mixer: AudioMixer
    @ObservedObject var state: MixerViewState
    @State private var expanded: Expanded?
    @State private var savingName: String?
    @State private var groupDraft: GroupDraft?
    @State private var listHeight: CGFloat = 0

    /// `expandedApp` is the app whose row starts open.
    init(mixer: AudioMixer, state: MixerViewState, expandedApp: String? = nil) {
        self.mixer = mixer
        self.state = state
        _expanded = State(initialValue: expandedApp.map(Expanded.app))
    }


    var body: some View {
        VStack(spacing: Space.s) {
            ScrollView {
                VStack(spacing: Space.s) {
                    systemGroup
                    appsGroup
                }
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { listHeight = $0 }
            }
            .scrollIndicators(.never)
            .frame(height: min(max(listHeight, 1), MixerStyle.listMaxHeight))
            footer
        }
        .padding(MixerStyle.screenInset)
        .frame(width: MixerStyle.width)
        .foregroundStyle(Ink.primary)
        .overlay {
            if let draft = groupDraft {
                OutputGroupEditor(mixer: mixer, draft: draft) { groupDraft = nil }
            }
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: Space.s) {
            if let name = savingName {
                TextField("Name for these settings", text: Binding(get: { name }, set: { savingName = $0 }))
                    .textFieldStyle(.roundedBorder).frame(maxWidth: 220)
                    .onSubmit(saveConfig)
                RowButton(String(localized: "Save"), action: saveConfig).disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                RowButton(String(localized: "Cancel")) { savingName = nil }
                Spacer()
            } else {
                PillMenu(title: String(localized: "Add Favorite"), symbol: "star.fill") {
                    let candidates = mixer.favoriteCandidates()
                    if candidates.isEmpty { Text("No apps to add") }
                    ForEach(candidates, id: \.key) { app in Button(app.name) { mixer.toggleFavorite(app.key) } }
                }
                Spacer()
                PillMenu(title: String(localized: "Quick Configs"), symbol: "slider.horizontal.3") {
                    let configs = mixer.configuration.quickConfigs
                    ForEach(configs) { config in Button(config.name) { mixer.applyQuickConfig(config.id) } }
                    if !configs.isEmpty { Divider() }
                    Button("Save Current Settings…") { savingName = "" }
                    if !configs.isEmpty {
                        Menu("Delete") {
                            ForEach(configs) { config in Button(config.name, role: .destructive) { mixer.removeQuickConfig(config.id) } }
                        }
                    }
                }
            }
        }
    }

    private func saveConfig() {
        guard let name = savingName, mixer.saveQuickConfig(named: name) else { return }
        savingName = nil
    }

    // MARK: Groups

    private var systemGroup: some View {
        MixerGroup(title: String(localized: "System"), columns: [String(localized: "Volume"), "Boost", String(localized: "Device"), "FX"],
                   collapsed: Binding(get: { state.systemCollapsed }, set: { state.systemCollapsed = $0 })) {
            ForEach([DeviceRole.output, .input, .effects], id: \.self) { role in
                let open = expanded == .system(role)
                VStack(spacing: 0) {
                    SystemRow(mixer: mixer, meters: mixer.meters, role: role, open: open) { toggle(.system(role)) }
                    if open { SystemDetails(mixer: mixer, role: role) }
                }
                .background(open ? MixerStyle.expanded : .clear)
            }
            if let error = mixer.systemError {
                Label(error, systemImage: "exclamationmark.triangle.fill").font(.role(.detail)).foregroundStyle(Status.warning)
                    .padding(.horizontal, Space.m).padding(.vertical, Space.xs).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var appsGroup: some View {
        MixerGroup(title: String(localized: "Apps"), columns: [String(localized: "Volume"), "Boost", String(localized: "Send to another output"), "FX"],
                   collapsed: Binding(get: { state.appsCollapsed }, set: { state.appsCollapsed = $0 })) {
            if mixer.rows.isEmpty {
                Text("No apps are playing sound. Apps appear here when they play, and favorites are always shown.")
                    .font(.role(.secondary)).foregroundStyle(MixerStyle.quiet)
                    .frame(maxWidth: .infinity).padding(.vertical, Space.l)
            }
            ForEach(mixer.rows) { row in
                let open = expanded == .app(row.key)
                VStack(spacing: 0) {
                    AppRow(mixer: mixer, meters: mixer.meters, row: row, open: open,
                           onNewGroup: { groupDraft = GroupDraft() }) { toggle(.app(row.key)) }
                    if open { AppDetails(mixer: mixer, row: row) }
                }
                .background(open ? MixerStyle.expanded : .clear)
            }
        }
    }

    private func toggle(_ row: Expanded) {
        withAnimation(.easeOut(duration: 0.15)) { expanded = expanded == row ? nil : row }
    }
}

// MARK: - Building blocks

/// A rounded, collapsible group with its title and the column headers.
private struct MixerGroup<Content: View>: View {
    let title: String
    let columns: [String]
    @Binding var collapsed: Bool
    @ViewBuilder let content: Content

    var body: some View {
        Card { VStack(spacing: 0) {
            HStack(spacing: Space.s) {
                Button { withAnimation(.easeOut(duration: 0.15)) { collapsed.toggle() } } label: {
                    Image(systemName: collapsed ? "chevron.right" : "chevron.down").font(.role(.caption, weight: .bold))
                        .frame(width: 22, height: 22).background(MixerStyle.control, in: Circle())
                }
                .buttonStyle(.plain)
                Text(title).font(.role(.body, weight: .bold))
                Spacer(minLength: 0)
                if !collapsed {
                    ColumnHeader(columns[0], width: MixerStyle.volumeWidth)
                    ColumnHeader(columns[1], width: MixerStyle.boostWidth)
                    ColumnHeader(columns[2], width: MixerStyle.deviceWidth)
                    ColumnHeader(columns[3], width: MixerStyle.fxWidth)
                }
            }
            .padding(.horizontal, Space.s)
            .frame(height: 36)
            if !collapsed { content.padding(.bottom, Space.xs) }
        } }
        .clipShape(RoundedRectangle(cornerRadius: Radius.m, style: .continuous))
    }
}

private struct ColumnHeader: View {
    let title: String
    let width: CGFloat
    init(_ title: String, width: CGFloat) {
        self.title = title
        self.width = width
    }

    var body: some View {
        Text(title).font(.role(.detail)).foregroundStyle(MixerStyle.quiet).lineLimit(1).frame(width: width)
    }
}

/// The common columns of a line: star, meter, icon and name on the left; volume, boost, device and the chevron.
private struct RowLayout<Leading: View, Volume: View, Boost: View, Device: View>: View {
    let open: Bool
    let toggle: () -> Void
    @ViewBuilder let leading: Leading
    @ViewBuilder let volume: Volume
    @ViewBuilder let boost: Boost
    @ViewBuilder let device: Device

    var body: some View {
        HStack(spacing: MixerStyle.columnGap) {
            leading.frame(width: MixerStyle.nameWidth, alignment: .leading)
            // Wrapped so an empty column (no boost for the input) still takes its width.
            HStack(spacing: 0) { volume }.frame(width: MixerStyle.volumeWidth)
            HStack(spacing: 0) { boost }.frame(width: MixerStyle.boostWidth)
            HStack(spacing: 0) { device }.frame(width: MixerStyle.deviceWidth)
            Button(action: toggle) {
                Image(systemName: open ? "chevron.down" : "chevron.right").font(.role(.caption, weight: .bold))
                    .frame(width: 24, height: 24).background(MixerStyle.control, in: Circle()).contentShape(Circle())
            }
            .buttonStyle(.plain).frame(width: MixerStyle.fxWidth).help("Effects and options")
        }
        .padding(.horizontal, MixerStyle.rowInset)
        .frame(height: MixerStyle.rowHeight)
    }
}

private struct VolumeColumn: View {
    let volume: Double
    let muted: Bool
    var enabled = true
    var symbol = "speaker.wave.2.fill"
    var mutedSymbol = "speaker.slash.fill"
    let onMute: () -> Void
    let onChange: (Double) -> Void

    var body: some View {
        HStack(spacing: Space.xs) {
            Button(action: onMute) {
                Image(systemName: muted ? mutedSymbol : symbol).font(.role(.detail, weight: .medium))
                    .foregroundStyle(muted ? MixerStyle.muted : Ink.secondary)
                    .frame(width: 22, height: 22).contentShape(Rectangle())
            }
            .buttonStyle(.plain).help(muted ? String(localized: "Unmute") : String(localized: "Mute"))
            TrackSlider(value: volume, range: 0...1, fill: muted ? MixerStyle.muted : MixerStyle.accent, enabled: enabled, onChange: onChange)
            Text(enabled ? AudioGain.percentText(volume) : "-").font(.role(.detail, design: .rounded)).monospacedDigit()
                .frame(width: 38, alignment: .trailing)
        }
    }
}

/// The Magic Boost switch: a round button, lit when on.
private struct BoostButton: View {
    let on: Bool
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            Image(systemName: "chevron.up.2").font(.role(.detail, weight: .bold))
                .foregroundStyle(on ? Ink.onAccent : Ink.secondary)
                .frame(width: 28, height: 28).background(on ? MixerStyle.accent : MixerStyle.control, in: Circle())
        }
        .buttonStyle(.plain).help(on ? String(localized: "Turn Off Magic Boost") : String(localized: "Magic Boost: raises quiet sounds and leaves loud ones as they are"))
    }
}

/// A rounded menu button showing the current choice with its icon.
private struct DeviceMenu<Content: View>: View {
    let title: String
    let symbol: String
    var highlighted = false
    @ViewBuilder let content: Content

    var body: some View {
        Menu { content.labelStyle(.titleAndIcon) } label: {
            HStack(spacing: Space.s) {
                Image(systemName: symbol).font(.role(.detail)).frame(width: 16)
                Text(title).font(.role(.secondary)).lineLimit(1)
                Spacer(minLength: Space.xs)
                Image(systemName: "chevron.up.chevron.down").font(.role(.caption, weight: .semibold)).foregroundStyle(MixerStyle.quiet)
            }
            .foregroundStyle(highlighted ? MixerStyle.accent : Ink.primary)
            .padding(.horizontal, Space.s).frame(height: 28)
            .background(MixerStyle.control, in: Capsule())
            .contentShape(Capsule())
        }
        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden)
    }
}

private struct PillMenu<Content: View>: View {
    let title: String
    let symbol: String
    @ViewBuilder let content: Content

    var body: some View {
        Menu { content } label: {
            HStack(spacing: Space.xs) {
                Image(systemName: symbol).font(.role(.detail))
                Text(title).font(.role(.secondary, weight: .medium))
                Image(systemName: "chevron.down").font(.role(.caption, weight: .bold))
            }
            .padding(.horizontal, Space.m).frame(height: 28)
            .background(MixerStyle.control, in: Capsule())
            .contentShape(Capsule())
        }
        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
    }
}

private func choice(_ title: String, symbol: String? = nil, checked: Bool, action: @escaping () -> Void) -> some View {
    MenuChoice(title: title, symbol: symbol, checked: checked, action: action)
}

private func symbol(for device: AudioDevice, input: Bool = false) -> String {
    AudioDeviceKind(transport: device.transport).symbol(input: input)
}

// MARK: - System rows

private struct SystemRow: View {
    @ObservedObject var mixer: AudioMixer
    @ObservedObject var meters: MeterLevels
    let role: DeviceRole
    let open: Bool
    let toggle: () -> Void

    private var state: SystemDeviceState { mixer.state(role) }

    var body: some View {
        RowLayout(open: open, toggle: toggle) {
            HStack(spacing: Space.s) {
                Color.clear.frame(width: 18)
                LevelMeter(level: role == .output ? meters.level(AudioMixer.outputKey) : 0, hatched: role == .input)
                Image(systemName: icon).font(.role(.emphasis)).frame(width: 24)
                Text(title).font(.role(.body, weight: .medium))
                if let until = mixer.timedMutes[role == .output ? AudioMixer.outputKey : ""] { TimedMuteBadge(until: until) }
            }
        } volume: {
            switch role {
            case .output:
                VolumeColumn(volume: state.volume ?? 0, muted: state.muted ?? false, enabled: state.canSetVolume,
                             onMute: { mixer.toggleMute(.output) }, onChange: { mixer.setVolume(.output, $0) })
            case .input:
                VolumeColumn(volume: state.volume ?? 0, muted: state.muted ?? false, enabled: state.canSetVolume, symbol: "mic.fill", mutedSymbol: "mic.slash.fill",
                             onMute: { mixer.toggleMute(.input) }, onChange: { mixer.setVolume(.input, $0) })
            case .effects:
                VolumeColumn(volume: mixer.alertVolume ?? 0, muted: false, enabled: mixer.alertVolume != nil,
                             onMute: {}, onChange: { mixer.setAlertVolume($0) })
            }
        } boost: {
            if role == .output {
                BoostButton(on: mixer.configuration.system.magicBoost) { mixer.updateSystemEffects { $0.magicBoost.toggle() } }
            }
        } device: {
            deviceMenu
        }
    }

    private var title: String {
        switch role {
        case .output: return String(localized: "Output")
        case .input: return String(localized: "Input")
        case .effects: return String(localized: "Alerts")
        }
    }

    private var icon: String {
        switch role {
        case .output: return "hifispeaker"
        case .input: return "mic"
        case .effects: return "bell"
        }
    }

    @ViewBuilder private var deviceMenu: some View {
        let follows = role == .effects && mixer.configuration.effectsFollowOutput
        let current = state.device
        DeviceMenu(title: follows ? String(localized: "Same as Output") : current?.name ?? String(localized: "None"),
                   symbol: follows ? "arrow.up" : current.map { symbol(for: $0, input: role == .input) } ?? "speaker.slash") {
            if role == .effects {
                choice(String(localized: "Same as Output"), symbol: "arrow.up", checked: follows) { mixer.setEffectsFollowOutput(true) }
                Divider()
            }
            ForEach(mixer.devices(for: role)) { device in
                choice(device.name, symbol: symbol(for: device, input: role == .input), checked: !follows && device.id == current?.id) {
                    if role == .effects { mixer.setEffectsFollowOutput(false) }
                    mixer.select(role, device)
                }
            }
        }
    }
}

/// What opens under a system line: the sample rate, the effect cards, and the actions.
private struct SystemDetails: View {
    @ObservedObject var mixer: AudioMixer
    let role: DeviceRole

    private var state: SystemDeviceState { mixer.state(role) }

    var body: some View {
        VStack(spacing: Space.s) {
            if let rate = state.sampleRate, !state.sampleRates.isEmpty {
                HStack {
                    Spacer()
                    Text("Sample Rate").font(.role(.secondary, weight: .medium))
                    DeviceMenu(title: "\(Int(rate)) Hz", symbol: "waveform") {
                        ForEach(state.sampleRates, id: \.self) { value in
                            choice("\(Int(value)) Hz", checked: value == rate) { mixer.setSampleRate(role, value) }
                        }
                    }
                    .frame(width: 200)
                }
            }
            if role == .output {
                let system = mixer.configuration.system
                if state.canSetBalance, let balance = state.balance {
                    EffectCard(title: "Balance", on: Binding(get: { true }, set: { if !$0 { mixer.setBalance(.output, 0) } }), onRemove: nil) {
                        BalanceControl(balance: balance) { mixer.setBalance(.output, $0) }
                    }
                }
                if system.effects.contains(.equalizer) {
                    EffectCard(title: EffectKind.equalizer.title,
                               on: Binding(get: { !system.bypassed.contains(.equalizer) }, set: { on in mixer.updateSystemEffects { if on { $0.bypassed.remove(.equalizer) } else { $0.bypassed.insert(.equalizer) } } }),
                               onRemove: { mixer.updateSystemEffects { $0.effects.removeAll { $0 == .equalizer }; $0.eq = .flat } }) {
                        EqualizerControl(eq: system.eq) { eq in mixer.updateSystemEffects { $0.eq = eq } }
                    }
                }
                HStack(spacing: Space.s) {
                    PillMenu(title: String(localized: "Add Effect"), symbol: "plus") {
                        if system.effects.contains(.equalizer) { Text("No effects to add") }
                        if !system.effects.contains(.equalizer) {
                            Button(EffectKind.equalizer.title) { mixer.updateSystemEffects { $0.effects.append(.equalizer) } }
                        }
                    }
                    Spacer()
                    TimedMuteMenu(mixer: mixer, key: AudioMixer.outputKey)
                    PillMenu(title: String(localized: "Options"), symbol: "gearshape.2") {
                        Button("Reset All Effects") { mixer.updateSystemEffects { $0 = SystemEffects() } }
                    }
                }
            } else if role == .effects {
                Text("The alert volume is a share of the output volume.").font(.role(.detail)).foregroundStyle(MixerStyle.quiet).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, Space.m).padding(.bottom, Space.s)
    }
}

// MARK: - App rows

private struct AppRow: View {
    @ObservedObject var mixer: AudioMixer
    @ObservedObject var meters: MeterLevels
    let row: MixerAppRow
    let open: Bool
    let onNewGroup: () -> Void
    let toggle: () -> Void

    private var settings: AppAudioSettings { row.settings }

    var body: some View {
        RowLayout(open: open, toggle: toggle) {
            HStack(spacing: Space.s) {
                Button { mixer.toggleFavorite(row.key) } label: {
                    Image(systemName: row.row.isFavorite ? "star.fill" : "star").font(.role(.secondary))
                        .foregroundStyle(row.row.isFavorite ? MixerStyle.accent : Ink.disabled).frame(width: 18)
                }
                .buttonStyle(.plain).help(row.row.isFavorite ? String(localized: "Remove from Favorites") : String(localized: "Pin to Favorites"))
                LevelMeter(level: meters.level(row.key))
                icon
                Text(row.name).font(.role(.body, weight: .medium)).lineLimit(1)
                    .opacity(row.row.group == nil || (!row.row.isPlaying && row.row.isRecent) ? 0.6 : 1)
                if let until = row.timedMuteUntil { TimedMuteBadge(until: until) }
                if row.routeError != nil {
                    Image(systemName: "exclamationmark.triangle.fill").font(.role(.detail)).foregroundStyle(Status.warning).help(row.routeError ?? "")
                }
            }
        } volume: {
            VolumeColumn(volume: settings.volume, muted: settings.muted || row.timedMuteUntil != nil,
                         onMute: { mixer.updateApp(row.key) { $0.muted.toggle() } }, onChange: { value in mixer.updateApp(row.key) { $0.volume = value } })
        } boost: {
            BoostButton(on: settings.magicBoost) { mixer.updateApp(row.key) { $0.magicBoost.toggle() } }
        } device: {
            redirectMenu
        }
    }

    @ViewBuilder private var icon: some View {
        if let path = row.appPath {
            Image(nsImage: NSWorkspace.shared.icon(forFile: path)).resizable().frame(width: 24, height: 24)
        } else {
            Image(systemName: "app.dashed").font(.role(.heading)).foregroundStyle(MixerStyle.quiet).frame(width: 24, height: 24)
        }
    }

    private var redirectMenu: some View {
        let current = settings.outputUID
        let groups = mixer.configuration.outputGroups
        let outputs = mixer.devices(for: .output)
        let regular = outputs.filter { AudioDeviceKind(transport: $0.transport) != .airPlay }
        let airPlay = outputs.filter { AudioDeviceKind(transport: $0.transport) == .airPlay }
        let title: String
        let icon: String
        if let current, let group = groups.first(where: { $0.reference == current }) {
            (title, icon) = (group.name, "square.stack.3d.up")
        } else if let current, let device = outputs.first(where: { $0.uid == current }) {
            (title, icon) = (device.name, symbol(for: device))
        } else if current != nil {
            (title, icon) = (String(localized: "Not connected"), "exclamationmark.triangle")
        } else {
            (title, icon) = (String(localized: "Not sent"), "arrow.up")
        }
        return DeviceMenu(title: title, symbol: icon, highlighted: current != nil) {
            choice(String(localized: "Not Sent (System Output)"), symbol: "arrow.up", checked: current == nil) { mixer.updateApp(row.key) { $0.outputUID = nil } }
            Divider()
            ForEach(regular) { device in
                choice(device.name, symbol: symbol(for: device), checked: device.uid == current) { mixer.updateApp(row.key) { $0.outputUID = device.uid } }
            }
            Section("AirPlay") {
                if airPlay.isEmpty { Text("AirPlay devices appear here once you choose them in Control Center") }
                ForEach(airPlay) { device in
                    choice(device.name, symbol: "airplayaudio", checked: device.uid == current) { mixer.updateApp(row.key) { $0.outputUID = device.uid } }
                }
            }
            Section("Output Groups") {
                ForEach(groups) { group in
                    choice(group.name, symbol: "square.stack.3d.up", checked: group.reference == current) { mixer.updateApp(row.key) { $0.outputUID = group.reference } }
                }
                Button(action: onNewGroup) { Label("New Output Group…", systemImage: "plus.square.on.square") }
            }
        }
        .help("Send only this app’s sound to another output device")
    }
}

/// What opens under an app line: its effect cards, then adding effects, timed mute and options.
private struct AppDetails: View {
    @ObservedObject var mixer: AudioMixer
    let row: MixerAppRow

    private var settings: AppAudioSettings { row.settings }

    var body: some View {
        VStack(spacing: Space.s) {
            if row.outputMissing {
                Text("The chosen output device is not connected, so the sound plays on the system output. It goes back when the device reconnects.")
                    .font(.role(.detail)).foregroundStyle(MixerStyle.quiet).frame(maxWidth: .infinity, alignment: .leading)
            }
            if let error = row.routeError {
                Label(error, systemImage: "exclamationmark.triangle.fill").font(.role(.detail)).foregroundStyle(Status.warning).frame(maxWidth: .infinity, alignment: .leading)
            }
            ForEach(settings.effects) { effect in
                EffectCard(title: effect.title, on: binding(effect), onRemove: { remove(effect) }) {
                    switch effect {
                    case .overdrive:
                        OverdriveControl(value: settings.overdrive) { value in mixer.updateApp(row.key) { $0.overdrive = value } }
                    case .equalizer:
                        EqualizerControl(eq: settings.eq) { eq in mixer.updateApp(row.key) { $0.eq = eq } }
                    case .balance:
                        BalanceControl(balance: settings.balance) { value in mixer.updateApp(row.key) { $0.balance = value } }
                    }
                }
            }
            HStack(spacing: Space.s) {
                PillMenu(title: String(localized: "Add Effect"), symbol: "plus") {
                    let missing = EffectKind.forApps.filter { !settings.effects.contains($0) }
                    if missing.isEmpty { Text("No effects to add") }
                    ForEach(missing) { effect in Button(effect.title) { mixer.updateApp(row.key) { $0.effects.append(effect) } } }
                }
                Spacer()
                TimedMuteMenu(mixer: mixer, key: row.key)
                PillMenu(title: String(localized: "Options"), symbol: "gearshape.2") {
                    let allOff = settings.effects.allSatisfy(settings.bypassed.contains)
                    Button(allOff ? String(localized: "Turn On All Effects") : String(localized: "Turn Off All Effects")) {
                        mixer.updateApp(row.key) { $0.bypassed = allOff ? [] : Set($0.effects) }
                    }
                    if row.row.isFavorite {
                        Divider()
                        Button("Move Up in Favorites") { mixer.moveFavorite(row.key, by: -1) }
                        Button("Move Down in Favorites") { mixer.moveFavorite(row.key, by: 1) }
                    }
                    Divider()
                    Button("Reset This App", role: .destructive) { mixer.resetApp(row.key) }
                }
            }
        }
        .padding(.horizontal, Space.m).padding(.bottom, Space.s)
    }

    private func binding(_ effect: EffectKind) -> Binding<Bool> {
        Binding(get: { !settings.bypassed.contains(effect) }, set: { on in
            mixer.updateApp(row.key) { if on { $0.bypassed.remove(effect) } else { $0.bypassed.insert(effect) } }
        })
    }

    /// Taking a card off puts its value back to neutral, so it changes nothing while away.
    private func remove(_ effect: EffectKind) {
        mixer.updateApp(row.key) { settings in
            settings.effects.removeAll { $0 == effect }
            settings.bypassed.remove(effect)
            switch effect {
            case .overdrive: settings.overdrive = 1
            case .equalizer: settings.eq = .flat
            case .balance: settings.balance = 0
            }
        }
    }
}

// MARK: - Effect cards

/// One effect: its switch and name, its control on the right, and × to take it off.
private struct EffectCard<Control: View>: View {
    let title: String
    let on: Binding<Bool>
    let onRemove: (() -> Void)?
    @ViewBuilder let control: Control

    var body: some View {
        HStack(spacing: Space.m) {
            TrackSwitch(isOn: on)
            Text(title).font(.role(.body, weight: .semibold)).lineLimit(1).layoutPriority(1)
            Spacer(minLength: Space.s)
            control.opacity(on.wrappedValue ? 1 : 0.45)
            if let onRemove {
                Button(action: onRemove) {
                    Image(systemName: "xmark").font(.role(.caption, weight: .bold)).frame(width: 24, height: 24).background(MixerStyle.control, in: Circle())
                }
                .buttonStyle(.plain).help("Remove this effect")
            }
        }
        .padding(.horizontal, Space.m).padding(.vertical, Space.s)
        .background(Shade.medium, in: Capsule())
    }
}

private struct OverdriveControl: View {
    let value: Double
    let choose: (Double) -> Void

    var body: some View {
        HStack(spacing: Space.xs) {
            ForEach(AudioGain.overdrives, id: \.self) { step in
                Button { choose(step) } label: {
                    Text(AudioGain.overdriveText(step)).font(.role(.secondary, weight: .semibold))
                        .foregroundStyle(step == value ? Ink.onAccent : Ink.secondary)
                        .frame(width: 40, height: 24)
                        .background(step == value ? MixerStyle.accent : .clear, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(Space.xs).background(MixerStyle.control, in: Capsule())
    }
}

private struct BalanceControl: View {
    let balance: Double
    let onChange: (Double) -> Void

    var body: some View {
        HStack(spacing: Space.s) {
            Text(label).font(.role(.secondary)).monospacedDigit().frame(width: 72, alignment: .trailing)
            Text(verbatim: "L").font(.role(.detail, weight: .semibold)).foregroundStyle(MixerStyle.quiet).fixedSize()
            TrackSlider(value: balance, range: -1...1, fill: MixerStyle.accent, fillsFromCentre: true) { onChange(abs($0) < 0.04 ? 0 : $0) }
                .frame(width: 120)
            Text(verbatim: "R").font(.role(.detail, weight: .semibold)).foregroundStyle(MixerStyle.quiet).fixedSize()
        }
    }

    private var label: String {
        let percent = Int((abs(balance) * 100).rounded())
        if abs(balance) < 0.01 { return String(localized: "Center") }
        return balance < 0 ? String(localized: "Left \(percent)%") : String(localized: "Right \(percent)%")
    }
}

/// The preset menu; "Adjust" opens the ten bands under it.
private struct EqualizerControl: View {
    let eq: EQSettings
    let onChange: (EQSettings) -> Void
    @State private var editing = false

    var body: some View {
        HStack(spacing: Space.s) {
            Text("Preset").font(.role(.secondary)).fixedSize()
            DeviceMenu(title: eq.preset.map { $0 == .flat ? String(localized: "Flat (Off)") : $0.title } ?? String(localized: "Custom"), symbol: eq.isFlat ? "minus" : "slider.vertical.3") {
                ForEach(EQPreset.allCases) { preset in
                    choice(preset == .flat ? String(localized: "Flat (Off)") : preset.title, checked: eq.preset == preset) { onChange(preset.settings) }
                }
            }
            .frame(width: 160)
            RowButton(editing ? String(localized: "Close") : String(localized: "Adjust")) { editing.toggle() }.fixedSize()
                .popover(isPresented: $editing, arrowEdge: .bottom) { EqualizerBands(eq: eq, onChange: onChange).padding(Space.m) }
        }
    }
}

/// Ten bands as small vertical bars, dragged up and down; a double click puts one back to 0 dB.
private struct EqualizerBands: View {
    let eq: EQSettings
    let onChange: (EQSettings) -> Void

    var body: some View {
        HStack(spacing: Space.xs) {
            ForEach(EQSettings.frequencies.indices, id: \.self) { band in
                VStack(spacing: Space.xs) {
                    Text(String(format: "%+.0f", eq.gains[band])).font(.role(.caption)).monospacedDigit().foregroundStyle(MixerStyle.quiet)
                    EQBandBar(gain: eq.gains[band]) { gain in
                        var next = eq
                        next.setGain(gain, band: band)
                        onChange(next)
                    }
                    Text(EQSettings.label(band: band)).font(.role(.caption)).foregroundStyle(MixerStyle.quiet)
                }
                .frame(width: 26)
            }
        }
    }
}

private struct EQBandBar: View {
    let gain: Double
    let onChange: (Double) -> Void
    private var range: Double { EQSettings.gainRange.upperBound }

    var body: some View {
        GeometryReader { proxy in
            let mid = proxy.size.height / 2
            let y = mid - CGFloat(gain / range) * mid
            ZStack(alignment: .top) {
                Capsule().fill(Fill.control).frame(width: 4)
                Rectangle().fill(Ink.disabled).frame(width: 12, height: 1).offset(y: mid)
                Rectangle().fill(MixerStyle.accent).frame(width: 4, height: abs(y - mid)).offset(y: min(y, mid))
                Circle().fill(Color.white).frame(width: 10, height: 10).offset(y: y - 5)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                onChange((Double((mid - value.location.y) / mid) * range * 2).rounded() / 2)
            })
            .onTapGesture(count: 2) { onChange(0) }
        }
        .frame(height: 110)
    }
}

private struct TimedMuteMenu: View {
    @ObservedObject var mixer: AudioMixer
    let key: String

    var body: some View {
        PillMenu(title: String(localized: "Mute For"), symbol: "timer") {
            Button("30 Seconds") { mixer.muteFor(key, seconds: 30) }
            Button("1 Minute") { mixer.muteFor(key, seconds: 60) }
            Button("2 Minutes") { mixer.muteFor(key, seconds: 120) }
            if mixer.timedMutes[key] != nil {
                Divider()
                Button("Unmute Now") { mixer.cancelTimedMute(key) }
            }
        }
        .help("Mutes the sound for a set time, then fades it back in")
    }
}

private struct TimedMuteBadge: View {
    let until: Date

    var body: some View {
        Text(timerInterval: Date()...max(until, Date()), countsDown: true).font(.role(.caption, weight: .semibold)).monospacedDigit()
            .foregroundStyle(MixerStyle.muted).padding(.horizontal, Space.xs).frame(height: 18).background(MixerStyle.muted.opacity(0.15), in: Capsule())
            .fixedSize()
    }
}

// MARK: - Output groups

struct GroupDraft: Equatable {
    var id: UUID?
    var name = ""
    var deviceUIDs: [String] = []
}

/// Choosing the devices of a new output group, over the mixer.
private struct OutputGroupEditor: View {
    @ObservedObject var mixer: AudioMixer
    @State var draft: GroupDraft
    let close: () -> Void

    var body: some View {
        ZStack {
            Shade.strong.onTapGesture(perform: close)
            VStack(alignment: .leading, spacing: Space.s) {
                Text("New Output Group").font(.role(.emphasis, weight: .bold))
                Text("The same sound plays on every chosen device. The first device keeps the time.").font(.role(.detail)).foregroundStyle(MixerStyle.quiet)
                TextField("Name (for example, Speakers and Headphones)", text: $draft.name).textFieldStyle(.roundedBorder)
                VStack(alignment: .leading, spacing: Space.xs) {
                    ForEach(mixer.devices(for: .output)) { device in
                        LabeledSwitch(title: device.name, isOn: Binding(get: { draft.deviceUIDs.contains(device.uid) }, set: { on in
                            if on { draft.deviceUIDs.append(device.uid) } else { draft.deviceUIDs.removeAll { $0 == device.uid } }
                        }))
                    }
                }
                HStack {
                    if !mixer.configuration.outputGroups.isEmpty {
                        Menu("Delete Group") {
                            ForEach(mixer.configuration.outputGroups) { group in Button(group.name, role: .destructive) { mixer.removeOutputGroup(group.id) } }
                        }
                        .fixedSize()
                    }
                    Spacer()
                    Button("Cancel", action: close)
                    Button("Create") {
                        if mixer.saveOutputGroup(id: draft.id, name: draft.name, deviceUIDs: draft.deviceUIDs) != nil { close() }
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(draft.name.trimmingCharacters(in: .whitespaces).isEmpty || draft.deviceUIDs.count < 2)
                }
            }
            .padding(Space.l)
            .frame(width: 380)
            .background(Surface.ground, in: RoundedRectangle(cornerRadius: Radius.m, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Radius.m, style: .continuous).strokeBorder(Line.base))
        }
    }
}
