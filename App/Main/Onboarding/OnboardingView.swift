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
                Copy(eyebrow: "시작", title: "키 하나로\n전부 부릅니다",
                     lead: "앱을 열고, 창을 나누고, 복사했던 것을 찾고, 화면을 찍고, 묻습니다. 어느 앱 위에서든.")
                HStack(spacing: Space.m) {
                    ForEach(Array(launcherKeys.enumerated()), id: \.offset) { _, key in Keycap(label: key, lit: model.hotkeyPressed) }
                }
                .padding(.top, Space.s)
                Group {
                    if model.hotkeyPressed {
                        Label("좋습니다. 이 키가 입력창을 엽니다.", systemImage: "checkmark")
                    } else {
                        Text("지금 눌러 보세요")
                    }
                }
                .font(.role(.body, weight: .medium))
                .foregroundStyle(model.hotkeyPressed ? GuideInk.positive : GuideInk.secondary)
            } art: {
                LauncherArt(lit: model.hotkeyPressed)
            }
        case .permissions:
            Split {
                Copy(eyebrow: "권한", title: "macOS 의\n허락 세 가지",
                     lead: "창을 옮기고 화면을 찍으려면 맥이 허락해야 합니다. 꼭 필요한 것은 손쉬운 사용 하나이고, 나머지는 그 기능을 쓸 때만 필요합니다. 나중에 설정 → 권한 에서도 켭니다.")
            } art: {
                VStack(spacing: 0) {
                    PermissionRow(title: "손쉬운 사용", detail: "창 옮기기, 바로 붙여넣기", required: true, granted: model.accessibility) {
                        AccessibilityPermission.prompt()
                        AccessibilityPermission.openSystemSettings()
                    }
                    GuideInk.hairline.frame(height: 1)
                    PermissionRow(title: "화면 기록", detail: "캡처와 녹화. 켠 뒤 앱을 다시 엽니다", required: false, granted: model.screenRecording) {
                        ScreenCapturePermission.request()
                        ScreenCapturePermission.openSystemSettings()
                    }
                    GuideInk.hairline.frame(height: 1)
                    PermissionRow(title: "클립보드 읽기", detail: model.clipboard ? "복사한 것을 이 맥에만 기록" : "시스템 설정의 「다른 앱에서 붙여넣기」 에서 허용",
                                  required: false, granted: model.clipboard, action: nil)
                }
                .panel()
            }
        case .tour:
            Split {
                Copy(eyebrow: "둘러보기", title: "이름으로 찾고\n키로 부릅니다",
                     lead: "모든 기능은 입력창에서 이름으로 찾을 수 있습니다. 자주 쓰는 것에는 단축키가 있고, 설정에서 바꿉니다.")
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
                Copy(eyebrow: "AI 검색", title: "점을 찍고\n물어보세요",
                     lead: "입력창 맨 앞에 . 을 치면 웹을 검색해 최신 정보로 답합니다. OpenRouter 키가 필요하고, 키는 이 맥의 키체인에만 둡니다.")
                AIKeyField(model: model).padding(.top, Space.xs)
            } art: {
                AnswerArt()
            }
        case .privacy:
            Split {
                Copy(eyebrow: "개인정보", title: "기록은\n이 맥에만",
                     lead: "클립보드, 사용 시간, 시스템 모니터 기록은 이 맥에만 남고 어디로도 보내지 않습니다. 무엇을 남길지 지금 고르고, 나중에 설정 → 개인정보와 저장 공간 에서 바꿉니다.")
            } art: {
                VStack(spacing: 0) {
                    ChoiceRow(title: "사용 시간 기록", detail: "어느 앱을 얼마나 썼는지. 90일 뒤 지웁니다", isOn: settings.moduleBinding(ScreenTimeModule.descriptor))
                    GuideInk.hairline.frame(height: 1)
                    ChoiceRow(title: "공용 IP 주소 확인", detail: "네트워크 자세히 보기에서 Cloudflare 에 묻습니다", isOn: settings.binding(\.publicAddressLookup))
                    GuideInk.hairline.frame(height: 1)
                    ChoiceRow(title: "로그인할 때 자동 실행", detail: "맥을 켜면 메뉴 막대에서 기다립니다", isOn: Binding(
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
                Text("준비됐습니다").font(.role(.figure, weight: .semibold)).kerning(-0.8)
                HStack(spacing: Space.s) {
                    Text("언제든")
                    ForEach(Array(launcherKeys.enumerated()), id: \.offset) { _, key in KeyHint(key) }
                    Text("를 누르세요. 설정은 메뉴 막대 아이콘을 오른쪽 클릭하거나 입력창에서 ⌘, 입니다.")
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
                Button("이전") { model.go(model.step.previous) }.buttonStyle(GhostButton())
            }
            if model.step.isLast {
                Button("시작하기", action: onFinish).buttonStyle(SolidButton()).keyboardShortcut(.defaultAction)
            } else {
                let skipping = model.step == .welcome && !model.hotkeyPressed
                // Without the one required permission the app still runs, with window actions off.
                let limited = model.step == .permissions && !model.accessibility
                Button(skipping ? "건너뛰기" : limited ? "권한 없이 계속" : "계속") { model.go(model.step.next) }
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
                    Text(required ? "필요" : "선택")
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
                Text("허락됨").font(.role(.secondary)).foregroundStyle(GuideInk.secondary)
            } else if let action {
                Button("허락하기", action: action).buttonStyle(SolidButton(compact: true))
            } else {
                Text("확인 필요").font(.role(.secondary)).foregroundStyle(Status.warning)
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
                Label("키가 준비되어 있습니다", systemImage: "checkmark").font(.role(.body, weight: .medium)).foregroundStyle(GuideInk.positive)
            } else {
                HStack(spacing: Space.s) {
                    SecureField("sk-or-…", text: $draft)
                        .textFieldStyle(.plain)
                        .font(.role(.body, design: .monospaced))
                        .padding(.horizontal, Space.m)
                        .frame(height: 34)
                        .background(GuideInk.surface, in: RoundedRectangle(cornerRadius: Radius.s, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: Radius.s, style: .continuous).strokeBorder(GuideInk.hairline, lineWidth: 1))
                        .onSubmit(save)
                    Button("저장", action: save).buttonStyle(SolidButton(compact: true)).disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                Text(failed ? "키를 저장하지 못했습니다." : "없으면 건너뛰고 나중에 설정의 AI 검색에서 넣습니다.")
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
        ("rectangle.lefthalf.filled", "왼쪽 절반", "⌃⌥←"), ("doc.on.clipboard", "클립보드 기록", "⌥V"),
        ("camera.viewfinder", "영역 캡처", "⌥⇧4"), ("app.dashed", "Slack", nil),
    ]

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Text("왼").font(.role(.title, weight: .medium))
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
                    Text("AI").font(.role(.detail, weight: .semibold))
                }
                .foregroundStyle(Brand.lavender)
                .padding(.horizontal, Space.s)
                .frame(height: 22)
                .background(Tint.wash(Brand.lavender), in: Capsule())
                Text("오늘 원달러 환율").font(.role(.heading, weight: .medium)).foregroundStyle(Brand.gradient)
                Spacer()
            }
            .padding(.horizontal, Space.l)
            .frame(height: 52)
            GuideInk.hairline.frame(height: 1)
            VStack(alignment: .leading, spacing: Space.m) {
                Text("오늘 원/달러 환율은 1,382.5원입니다. 전일보다 3.2원 올랐고, 장중 1,379원에서 1,385원 사이에서 움직였습니다.")
                    .font(.role(.body)).lineSpacing(4).foregroundStyle(Tint.strong(GuideInk.primary))
                HStack(spacing: Space.s) {
                    ForEach(["1  investing.com", "2  한국은행"], id: \.self) { source in
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
