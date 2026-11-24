import AppKit
import ToolsmithKit

/// The mixer in the launcher: open it, switch the output or input device, bring back a Quick Config.
@MainActor final class AudioCommandSource: CommandSource {
    static let section = CommandSection(id: "audio", title: "소리", order: 6)
    static let openID = "audio.mixer"
    private let mixer: AudioMixer
    var openMixer: () -> Void = {}

    init(mixer: AudioMixer) {
        self.mixer = mixer
    }

    nonisolated func commands() -> [Command] {
        MainActor.assumeIsolated {
            var commands = [
                Command(id: Self.openID, title: "소리 조절 열기", subtitle: nil,
                        keywords: ["sound", "volume", "audio", "mixer", "soundsource", "소리", "볼륨", "음량", "오디오", "믹서", "이퀄라이저", "eq"],
                        section: Self.section, icon: .symbol("speaker.wave.2"), hotkeyID: Self.openID,
                        run: { [weak self] in self?.openMixer() }),
            ]
            commands += deviceCommands(.output, title: "출력", symbol: "hifispeaker", keywords: ["output", "speaker", "headphones", "출력", "스피커", "헤드폰", "이어폰"])
            commands += deviceCommands(.input, title: "입력", symbol: "mic", keywords: ["input", "microphone", "mic", "입력", "마이크"])
            commands += mixer.configuration.quickConfigs.map { config in
                Command(id: "audio.config:\(config.id.uuidString)", title: "소리 설정: \(config.name)", subtitle: "Quick Config 불러오기",
                        keywords: ["quick config", "소리 설정", "프리셋"], section: Self.section, icon: .symbol("square.stack.3d.up"), hotkeyID: nil,
                        run: { [weak self] in self?.mixer.applyQuickConfig(config.id) })
            }
            return commands
        }
    }

    private func deviceCommands(_ role: DeviceRole, title: String, symbol: String, keywords: [String]) -> [Command] {
        let current = mixer.state(role).device?.uid
        return mixer.devices(for: role).map { device in
            Command(id: "audio.\(title):\(device.uid)", title: "\(title): \(device.name)", subtitle: device.uid == current ? "지금 쓰는 장치" : nil,
                    keywords: keywords, section: Self.section, icon: .symbol(symbol), hotkeyID: nil, tracksUsage: false,
                    run: { [weak self] in self?.mixer.select(role, device) })
        }
    }
}
