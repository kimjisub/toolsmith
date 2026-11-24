import AppKit
import SwiftUI
import ToolsmithKit

/// The state of the first-run guide.
@MainActor final class OnboardingModel: ObservableObject {
    @Published var step: OnboardingStep = .welcome
    /// Whether the user pressed the launcher shortcut on the welcome page.
    @Published var hotkeyPressed = false
    @Published var accessibility = AccessibilityPermission.isGranted
    @Published var screenRecording = ScreenCapturePermission.isGranted
    @Published var clipboard = ClipboardMonitor.canRead
    @Published var hasKey = KeyStore.isAvailable
    /// True while the page is moving forward (decides which way pages slide).
    @Published var forward = true
    private var timer: Timer?

    func go(_ target: OnboardingStep) {
        forward = target.rawValue >= step.rawValue
        withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) { step = target }
    }

    /// The permissions are granted in another app; look again every second while the guide is open.
    func startWatching() {
        timer?.invalidate()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stopWatching() {
        timer?.invalidate()
        timer = nil
    }

    func refresh() {
        let values = (AccessibilityPermission.isGranted, ScreenCapturePermission.isGranted, ClipboardMonitor.canRead, KeyStore.isAvailable)
        if accessibility != values.0 { withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { accessibility = values.0 } }
        if screenRecording != values.1 { withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { screenRecording = values.1 } }
        if clipboard != values.2 { clipboard = values.2 }
        if hasKey != values.3 { hasKey = values.3 }
    }

    /// The launcher shortcut was pressed while the welcome page is showing.
    func launcherHotkeyPressed() {
        guard step == .welcome, !hotkeyPressed else { return }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.6)) { hotkeyPressed = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { [weak self] in
            if self?.step == .welcome { self?.go(.permissions) }
        }
    }
}

struct OnboardingView: View {
    @ObservedObject var model: OnboardingModel
    @ObservedObject var settings: SettingsStore
    var onFinish: () -> Void

    static let size = CGSize(width: 880, height: 540)
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var launcherKeys: [String] { settings.settings.hotkeys.combo(for: HotkeyID.openLauncher)?.displayParts ?? ["⌥", "Space"] }

    var body: some View {
        ZStack {
            Backdrop()
            VStack(spacing: 0) {
                header
                page
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .id(model.step)
                    .transition(reduceMotion ? .opacity : .asymmetric(
                        insertion: .offset(x: model.forward ? 24 : -24).combined(with: .opacity),
                        removal: .offset(x: model.forward ? -24 : 24).combined(with: .opacity)))
                footer
            }
        }
        // Fill the whole window, whatever its size, under the title bar too: any uncovered edge
        // shows as a separate strip.
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
        .foregroundStyle(GuideInk.primary)
        .environment(\.colorScheme, .dark)
        .onAppear { model.startWatching() }
        .onDisappear { model.stopWatching() }
    }

    /// The wordmark and where we are, in one quiet line.
    private var header: some View {
        HStack {
            Text(AppIdentity.name.uppercased()).font(.role(.detail, weight: .semibold, design: .monospaced)).kerning(2.2).foregroundStyle(GuideInk.tertiary)
            Spacer()
            Text(String(format: "%02d / %02d", model.step.rawValue + 1, OnboardingStep.allCases.count))
                .font(.role(.detail, weight: .medium, design: .monospaced)).kerning(1).foregroundStyle(GuideInk.tertiary)
        }
        .padding(.leading, Space.huge) // clear of the window's close button
        .padding(.trailing, Space.xxxl)
        .frame(height: 52)
    }

    @ViewBuilder private var page: some View {
        switch model.step {
        case .welcome:
            Split {
                AppIconImage(size: 72).padding(.bottom, -Space.xs)
                Copy(eyebrow: String(localized: "Welcome"), title: String(localized: "One key\nfor everything"),
                     lead: String(localized: "Open apps, arrange windows, find what you copied, capture the screen, ask questions. Over any app."))
                HStack(spacing: Space.m) {
                    ForEach(Array(launcherKeys.enumerated()), id: \.offset) { _, key in Keycap(label: key, lit: model.hotkeyPressed) }
                }
                .padding(.top, Space.s)
                Group {
                    if model.hotkeyPressed {
                        Label("Great. This key opens the launcher.", systemImage: "checkmark")
                    } else {
                        Text("Try pressing it now")
                    }
                }
                .font(.role(.body, weight: .medium))
                .foregroundStyle(model.hotkeyPressed ? GuideInk.positive : GuideInk.secondary)
            } art: {
                LauncherArt(lit: model.hotkeyPressed)
            }
        case .permissions:
            Split {
                Copy(eyebrow: String(localized: "Permissions"), title: String(localized: "Three permissions\nfrom macOS"),
                     lead: String(localized: "Moving windows and capturing the screen need your Mac’s permission. Only Accessibility is required; the others are needed only when you use those features. You can also turn them on later in Settings → Permissions."))
                Label("After you allow one, macOS may reopen the app. The guide continues from here.", systemImage: "arrow.clockwise")
                    .font(.role(.secondary))
                    .foregroundStyle(GuideInk.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            } art: {
                VStack(spacing: 0) {
                    PermissionRow(title: String(localized: "Accessibility"), detail: String(localized: "Moving windows, pasting directly"), required: true, granted: model.accessibility) {
                        AccessibilityPermission.prompt()
                        AccessibilityPermission.openSystemSettings()
                    }
                    GuideInk.hairline.frame(height: 1)
                    PermissionRow(title: String(localized: "Screen Recording"), detail: String(localized: "Capture and recording. The app reopens after you turn it on"), required: false, granted: model.screenRecording) {
                        ScreenCapturePermission.request()
                        ScreenCapturePermission.openSystemSettings()
                    }
                    GuideInk.hairline.frame(height: 1)
                    PermissionRow(title: String(localized: "Clipboard Access"), detail: model.clipboard ? String(localized: "Records what you copy on this Mac only") : String(localized: "Allow it in “Paste from Other Apps” in System Settings"),
                                  required: false, granted: model.clipboard, action: nil)
                }
                .panel()
            }
        case .tour:
            Split {
                Copy(eyebrow: String(localized: "Tour"), title: String(localized: "Find it by name,\ncall it with a key"),
                     lead: String(localized: "Every feature can be found by name in the launcher. The ones you use often have shortcuts, which you can change in Settings."))
            } art: {
                VStack(spacing: 0) {
                    let items = OnboardingTour.items(hotkeys: settings.settings.hotkeys)
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        if index > 0 { GuideInk.hairline.frame(height: 1) }
                        HStack(spacing: Space.m) {
                            Image(systemName: item.symbol).font(.role(.emphasis, weight: .medium)).foregroundStyle(GuideInk.secondary).frame(width: 22)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(item.title).font(.role(.body, weight: .medium))
                                Text(item.detail).font(.role(.secondary)).foregroundStyle(GuideInk.tertiary)
                            }
                            Spacer(minLength: Space.s)
                            if let keys = item.keys { KeyHint(keys) }
                        }
                        .padding(.horizontal, Space.l)
                        .frame(height: 52)
                    }
                }
                .panel()
            }
        case .ai:
            Split {
                Copy(eyebrow: String(localized: "AI Search"), title: String(localized: "Type a period\nand ask"),
                     lead: String(localized: "Type . at the start of the launcher to get answers searched on the web, up to date. It needs an OpenRouter key, which stays in this Mac’s keychain."))
                AIKeyField(model: model).padding(.top, Space.xs)
            } art: {
                AnswerArt()
            }
        case .privacy:
            Split {
                Copy(eyebrow: String(localized: "Privacy"), title: String(localized: "Your history\nstays on this Mac"),
                     lead: String(localized: "Clipboard, screen time and system monitor history stay on this Mac and are never sent anywhere. Choose what to keep now, and change it later in Settings → Privacy & Storage."))
            } art: {
                VStack(spacing: 0) {
                    ChoiceRow(title: String(localized: "Record Screen Time"), detail: String(localized: "How long you used each app. Deleted after 90 days"), isOn: settings.moduleBinding(ScreenTimeModule.descriptor))
                    GuideInk.hairline.frame(height: 1)
                    ChoiceRow(title: String(localized: "Look Up Public IP Address"), detail: String(localized: "Network details ask Cloudflare for it"), isOn: settings.binding(\.publicAddressLookup))
                    GuideInk.hairline.frame(height: 1)
                    ChoiceRow(title: String(localized: "Launch at Login"), detail: String(localized: "Waits in the menu bar when you start your Mac"), isOn: Binding(
                        get: { LaunchAtLogin.isInstalled ? LaunchAtLogin.isEnabled : settings.settings.launchAtLogin },
                        set: { value in
                            if LaunchAtLogin.isInstalled { try? LaunchAtLogin.set(value) }
                            settings.update { $0.launchAtLogin = value }
                        }))
                }
                .panel()
            }
        case .done:
            VStack(spacing: Space.l) {
                AppIconImage(size: 88)
                    .overlay(alignment: .bottomTrailing) {
                        Image(systemName: "checkmark")
                            .font(.role(.secondary, weight: .bold))
                            .foregroundStyle(GuideInk.background)
                            .frame(width: 26, height: 26)
                            .background(GuideInk.positive, in: Circle())
                            .offset(x: 4, y: 4)
                    }
                Text("You’re all set").font(.role(.figure, weight: .semibold)).kerning(-0.8)
                HStack(spacing: Space.s) {
                    Text("Press", comment: "Before the launcher keys: Press ⌥ Space anytime.")
                    ForEach(Array(launcherKeys.enumerated()), id: \.offset) { _, key in KeyHint(key) }
                    Text("anytime. For Settings, right-click the menu bar icon or press ⌘, in the launcher.", comment: "After the launcher keys: Press ⌥ Space anytime.")
                }
                .font(.role(.emphasis))
                .foregroundStyle(GuideInk.secondary)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: Space.m) {
            // Progress as thin segments: where we are without shouting.
            HStack(spacing: Space.xs) {
                ForEach(OnboardingStep.allCases, id: \.self) { step in
                    Capsule().fill(step.rawValue <= model.step.rawValue ? GuideInk.primary : GuideInk.hairline).frame(width: 26, height: 3)
                }
            }
            .animation(.easeOut(duration: 0.25), value: model.step)
            .accessibilityHidden(true)
            Spacer()
            if model.step != .welcome {
                Button("Back") { model.go(model.step.previous) }.buttonStyle(GhostButton())
            }
            if model.step.isLast {
                Button("Get Started", action: onFinish).buttonStyle(SolidButton()).keyboardShortcut(.defaultAction)
            } else {
                let skipping = model.step == .welcome && !model.hotkeyPressed
                // Without the one required permission the app still runs, with window actions off.
                let limited = model.step == .permissions && !model.accessibility
                Button(skipping ? "Skip" : limited ? "Continue Without Permission" : "Continue") { model.go(model.step.next) }
                    .buttonStyle(skipping ? AnyButtonStyle(GhostButton()) : AnyButtonStyle(SolidButton()))
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(.horizontal, Space.xxxl)
        .frame(height: 72)
        .overlay(alignment: .top) { GuideInk.hairline.frame(height: 1) }
    }
}

// MARK: Palette

/// The guide is almost monochrome. Color appears only where something is happening.
private enum GuideInk {
    static let background = Surface.deep
    static let primary = Ink.primary
    static let secondary = Ink.tertiary
    static let tertiary = Ink.disabled
    static let hairline = Fill.selected
    static let surface = Fill.card
    static let positive = Status.success
}

private extension View {
    /// A quiet raised surface with a hairline edge.
    func panel() -> some View {
        self.background(GuideInk.surface, in: RoundedRectangle(cornerRadius: Radius.l, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Radius.l, style: .continuous).strokeBorder(GuideInk.hairline, lineWidth: 1))
    }
}

// MARK: Layout

/// Words on the left, a picture of the thing on the right.
private struct Split<Words: View, Art: View>: View {
    @ViewBuilder var words: () -> Words
    @ViewBuilder var art: () -> Art

    var body: some View {
        HStack(alignment: .center, spacing: Space.huge) {
            VStack(alignment: .leading, spacing: Space.l) { words() }
                .frame(width: 330, alignment: .leading)
            art().frame(width: 366)
        }
        .padding(.horizontal, Space.huge)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct Copy: View {
    let eyebrow: String, title: String, lead: String

    var body: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            Text(eyebrow).font(.role(.secondary, weight: .medium)).foregroundStyle(Brand.lavender)
            Text(title)
                .font(.role(.figure, weight: .semibold))
                .kerning(-1)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
            Text(lead)
                .font(.role(.emphasis))
                .foregroundStyle(GuideInk.secondary)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: Pieces

/// A key as on the keyboard: a lit top edge, a darker body, a shadow underneath.
private struct Keycap: View {
    let label: String
    let lit: Bool

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.s, style: .continuous)
        Text(label)
            .font(.role(label.count > 1 ? .emphasis : .title, weight: .medium))
            .foregroundStyle(lit ? GuideInk.background : GuideInk.primary)
            .frame(minWidth: label.count > 1 ? 92 : 54, minHeight: 54)
            .background(shape.fill(lit ? AnyShapeStyle(Brand.gradient)
                                       : AnyShapeStyle(LinearGradient(colors: [Line.base, Fill.card], startPoint: .top, endPoint: .bottom))))
            .overlay(shape.strokeBorder(LinearGradient(colors: [lit ? Ink.tertiary : Line.strong, Fill.card], startPoint: .top, endPoint: .bottom), lineWidth: 1))
            .shadow(color: Shade.strong, radius: 0, y: lit ? 1 : 3)
            .shadow(color: lit ? Tint.light(Brand.lavender) : .clear, radius: 18)
            .offset(y: lit ? 2 : 0)
            .animation(.spring(response: 0.22, dampingFraction: 0.6), value: lit)
    }
}

/// A shortcut written small, the way menus write it.
private struct KeyHint: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.role(.secondary, weight: .medium))
            .kerning(1.2)
            .foregroundStyle(GuideInk.secondary)
            .padding(.horizontal, Space.s)
            .frame(height: 22)
            .background(Fill.control, in: RoundedRectangle(cornerRadius: Radius.xs, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Radius.xs, style: .continuous).strokeBorder(GuideInk.hairline, lineWidth: 1))
    }
}

private struct PermissionRow: View {
    let title: String, detail: String
    let required: Bool
    let granted: Bool
    let action: (() -> Void)?

    var body: some View {
        HStack(spacing: Space.m) {
            // The state as a mark, not a color wash over the whole row.
            ZStack {
                Circle().strokeBorder(granted ? GuideInk.positive : GuideInk.tertiary, lineWidth: 1.5)
                if granted { Image(systemName: "checkmark").font(.role(.caption, weight: .bold)).foregroundStyle(GuideInk.positive) }
            }
            .frame(width: 18, height: 18)
            VStack(alignment: .leading, spacing: Space.xs) {
                HStack(spacing: Space.s) {
                    Text(title).font(.role(.emphasis, weight: .medium))
                    Text(required ? "Required" : "Optional")
                        .font(.role(.caption, weight: .semibold))
                        .foregroundStyle(required ? Brand.peach : GuideInk.tertiary)
                        .padding(.horizontal, Space.s)
                        .frame(height: 17)
                        .background((required ? Brand.peach : Color.white).opacity(0.12), in: Capsule())
                }
                Text(detail).font(.role(.secondary)).foregroundStyle(GuideInk.tertiary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: Space.s)
            if granted {
                Text("Allowed").font(.role(.secondary)).foregroundStyle(GuideInk.secondary)
            } else if let action {
                Button("Allow", action: action).buttonStyle(SolidButton(compact: true))
            } else {
                Text("Needs attention").font(.role(.secondary)).foregroundStyle(Status.warning)
            }
        }
        .padding(.horizontal, Space.l)
        .frame(minHeight: 68)
    }
}

/// A choice with a switch, on the guide's dark panel.
private struct ChoiceRow: View {
    let title: String, detail: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: Space.m) {
            VStack(alignment: .leading, spacing: Space.xs) {
                Text(title).font(.role(.emphasis, weight: .medium))
                Text(detail).font(.role(.secondary)).foregroundStyle(GuideInk.tertiary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: Space.s)
            RowSwitch(title: title, isOn: $isOn)
        }
        .padding(.horizontal, Space.l)
        .frame(minHeight: 68)
    }
}

private struct AIKeyField: View {
    @ObservedObject var model: OnboardingModel
    @State private var draft = ""
    @State private var failed = false

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            if model.hasKey {
                Label("Your key is ready", systemImage: "checkmark").font(.role(.body, weight: .medium)).foregroundStyle(GuideInk.positive)
            } else {
                HStack(spacing: Space.s) {
                    SecureField(String("sk-or-…"), text: $draft)
                        .textFieldStyle(.plain)
                        .font(.role(.body, design: .monospaced))
                        .padding(.horizontal, Space.m)
                        .frame(height: 34)
                        .background(GuideInk.surface, in: RoundedRectangle(cornerRadius: Radius.s, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: Radius.s, style: .continuous).strokeBorder(GuideInk.hairline, lineWidth: 1))
                        .onSubmit(save)
                    Button("Save", action: save).buttonStyle(SolidButton(compact: true)).disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                Text(failed ? "Couldn’t save the key." : "If you don’t have one, skip this and add it later in AI Search in Settings.")
                    .font(.role(.secondary)).foregroundStyle(failed ? Brand.peach : GuideInk.tertiary)
            }
        }
    }

    private func save() {
        failed = !KeyStore.save(draft)
        if !failed { draft = "" }
        model.refresh()
    }
}

// MARK: Pictures

/// The launcher, drawn small: what the shortcut brings up.
private struct LauncherArt: View {
    let lit: Bool
    private let rows: [(String, String, String?)] = [
        ("rectangle.lefthalf.filled", String(localized: "Left Half"), "⌃⌥←"), ("doc.on.clipboard", String(localized: "Clipboard History"), "⌥V"),
        ("camera.viewfinder", String(localized: "Capture Area"), "⌥⇧4"), ("app.dashed", "Slack", nil),
    ]

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Text("Le", comment: "A query being typed in the launcher picture; the first row (Left Half) matches it.").font(.role(.title, weight: .medium))
                Rectangle().fill(GuideInk.primary).frame(width: 1.5, height: 21).padding(.leading, Space.xs)
                Spacer()
            }
            .padding(.horizontal, Space.l)
            .frame(height: 52)
            GuideInk.hairline.frame(height: 1)
            VStack(spacing: Space.xs) {
                ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                    HStack(spacing: Space.m) {
                        Image(systemName: row.0).font(.role(.body, weight: .medium)).frame(width: 20)
                        Text(row.1).font(.role(.body))
                        Spacer()
                        if let keys = row.2 { Text(keys).font(.role(.detail)).kerning(1).foregroundStyle(GuideInk.tertiary) }
                    }
                    .foregroundStyle(index == 0 ? GuideInk.primary : GuideInk.secondary)
                    .padding(.horizontal, Space.m)
                    .frame(height: 38)
                    .background(index == 0 ? Fill.control : Color.clear, in: RoundedRectangle(cornerRadius: Radius.s, style: .continuous))
                    .opacity(index < 2 ? 1 : (index == 2 ? 0.7 : 0.4))
                }
            }
            .padding(Space.s)
        }
        .background(Surface.deepCard, in: RoundedRectangle(cornerRadius: Radius.l, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.l, style: .continuous).strokeBorder(lit ? Line.strong : Line.base, lineWidth: 1))
        .shadow(color: Shade.strong, radius: 30, y: 18)
        .scaleEffect(lit ? 1 : 0.97)
        .opacity(lit ? 1 : 0.72)
        .animation(.spring(response: 0.4, dampingFraction: 0.75), value: lit)
        .accessibilityHidden(true)
    }
}

/// An answer with its sources, drawn small.
private struct AnswerArt: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Space.s) {
                HStack(spacing: Space.xs) {
                    Image(systemName: "sparkles").font(.role(.caption, weight: .semibold))
                    Text(verbatim: "AI").font(.role(.detail, weight: .semibold))
                }
                .foregroundStyle(Brand.lavender)
                .padding(.horizontal, Space.s)
                .frame(height: 22)
                .background(Tint.wash(Brand.lavender), in: Capsule())
                Text("USD to KRW today").font(.role(.heading, weight: .medium)).foregroundStyle(Brand.gradient)
                Spacer()
            }
            .padding(.horizontal, Space.l)
            .frame(height: 52)
            GuideInk.hairline.frame(height: 1)
            VStack(alignment: .leading, spacing: Space.m) {
                Text("Today’s USD/KRW rate is ₩1,382.5, up ₩3.2 from yesterday. It moved between ₩1,379 and ₩1,385 during the day.")
                    .font(.role(.body)).lineSpacing(4).foregroundStyle(Tint.strong(GuideInk.primary))
                HStack(spacing: Space.s) {
                    ForEach(["1  investing.com", String(localized: "2  Bank of Korea")], id: \.self) { source in
                        Text(source).font(.role(.detail)).foregroundStyle(GuideInk.secondary)
                            .padding(.horizontal, Space.s).frame(height: 22)
                            .background(Fill.control, in: Capsule())
                    }
                }
            }
            .padding(Space.l)
        }
        .background(Surface.deepCard, in: RoundedRectangle(cornerRadius: Radius.l, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.l, style: .continuous).strokeBorder(Line.base, lineWidth: 1))
        .shadow(color: Shade.strong, radius: 30, y: 18)
        .accessibilityHidden(true)
    }
}

/// Near black, with one soft light from above so the window is not a flat slab.
private struct Backdrop: View {
    var body: some View {
        ZStack {
            GuideInk.background
            RadialGradient(colors: [Fill.control, .clear], center: UnitPoint(x: 0.72, y: -0.1), startRadius: 0, endRadius: 520)
        }
    }
}

// MARK: Buttons

/// The one thing to do next: solid, light, no glow.
struct SolidButton: ButtonStyle {
    var compact = false
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.role(compact ? .secondary : .body, weight: .semibold))
            .foregroundStyle(Surface.deep)
            .padding(.horizontal, compact ? Space.m : Space.l)
            .frame(height: compact ? 28 : 34)
            .background(configuration.isPressed ? Ink.secondary : Ink.primary, in: RoundedRectangle(cornerRadius: compact ? Radius.xs : Radius.s, style: .continuous))
            .opacity(enabled ? 1 : 0.35)
    }
}

struct GhostButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.role(.body, weight: .medium))
            .foregroundStyle(configuration.isPressed ? Ink.disabled : Ink.tertiary)
            .padding(.horizontal, Space.l)
            .frame(height: 34)
            .contentShape(Rectangle())
    }
}

/// Lets a view pick between button styles at run time.
struct AnyButtonStyle: ButtonStyle {
    private let make: (Configuration) -> AnyView
    init<S: ButtonStyle>(_ style: S) { make = { AnyView(style.makeBody(configuration: $0)) } }
    func makeBody(configuration: Configuration) -> some View { make(configuration) }
}
