import AppKit
import ToolsmithKit

/// The mixer in the launcher: open it, switch the output or input device, bring back a Quick Config.
@MainActor final class AudioCommandSource: CommandSource {
    static let section = CommandSection(id: "audio", title: String(localized: "Sound"), order: 6)
    static let openID = "audio.mixer"
    private let mixer: AudioMixer
    var openMixer: () -> Void = {}

    init(mixer: AudioMixer) {
        self.mixer = mixer
    }

    nonisolated func commands() -> [Command] {
        MainActor.assumeIsolated {
            var commands = [
                Command(id: Self.openID, localizedTitle: "Open Sound", subtitle: nil,
                        keywords: ["sound", "volume", "audio", "mixer", "soundsource", "소리", "볼륨", "음량", "오디오", "믹서", "이퀄라이저", "eq"],
                        section: Self.section, icon: .symbol("speaker.wave.2"), hotkeyID: Self.openID,
                        run: { [weak self] in self?.openMixer() }),
            ]
            commands += deviceCommands(.output, idPrefix: "output", symbol: "hifispeaker", keywords: ["output", "speaker", "headphones", "출력", "스피커", "헤드폰", "이어폰"])
            commands += deviceCommands(.input, idPrefix: "input", symbol: "mic", keywords: ["input", "microphone", "mic", "입력", "마이크"])
            commands += mixer.configuration.quickConfigs.map { config in
                Command(id: "audio.config:\(config.id.uuidString)", title: String(localized: "Quick Config: \(config.name)"), subtitle: String(localized: "Load saved sound settings"),
                        keywords: ["quick config", "소리 설정", "프리셋"], section: Self.section, icon: .symbol("square.stack.3d.up"), hotkeyID: nil,
                        run: { [weak self] in self?.mixer.applyQuickConfig(config.id) })
            }
            return commands
        }
    }

    private func deviceCommands(_ role: DeviceRole, idPrefix: String, symbol: String, keywords: [String]) -> [Command] {
        let current = mixer.state(role).device?.uid
        return mixer.devices(for: role).map { device in
            Command(id: "audio.\(idPrefix):\(device.uid)", title: Self.deviceTitle(role, device.name), subtitle: device.uid == current ? String(localized: "In use") : nil,
                    keywords: keywords, section: Self.section, icon: .symbol(symbol), hotkeyID: nil, tracksUsage: false,
                    run: { [weak self] in self?.mixer.select(role, device) })
        }
    }

    private static func deviceTitle(_ role: DeviceRole, _ name: String) -> String {
        role == .input ? String(localized: "Input: \(name)") : String(localized: "Output: \(name)")
    }
}
