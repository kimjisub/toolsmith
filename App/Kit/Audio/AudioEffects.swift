import CoreAudio
import Foundation

/// An effect that sits on a line as a card of its own: switched on and off, or taken off the line.
public enum EffectKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case overdrive, equalizer, balance

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .overdrive: return "Volume Overdrive"
        case .equalizer: return "10-Band Equalizer"
        case .balance: return "Balance"
        }
    }

    /// Overdrive raises one app above the others; the system output has its own volume for that.
    public static let forApps: [EffectKind] = [.overdrive, .equalizer, .balance]
    public static let forOutput: [EffectKind] = [.equalizer, .balance]
}

/// Everything a route does to the sound, in one value: the processor's whole setting.
public struct EffectChain: Equatable, Sendable {
    /// Volume times overdrive (0 when muted).
    public var gain: Double = 1
    /// Equalizers applied one after the other (an app's own, then the system output's).
    public var equalizers: [EQSettings] = []
    /// −1 (left only) … 0 (centred) … 1 (right only).
    public var balance: Double = 0
    public var magicBoost = false
    /// How long a change of gain takes. A timed mute ending fades back in slowly.
    public var glide: Double = AudioGain.defaultGlide

    public init(gain: Double = 1, equalizers: [EQSettings] = [], balance: Double = 0, magicBoost: Bool = false, glide: Double = AudioGain.defaultGlide) {
        self.gain = gain
        self.equalizers = equalizers.filter { !$0.isFlat }
        self.balance = min(max(balance, -1), 1)
        self.magicBoost = magicBoost
        self.glide = glide
    }

    /// True when the sound passes through unchanged: such a route is not needed.
    public var isNeutral: Bool { abs(gain - 1) < 0.001 && equalizers.isEmpty && abs(balance) < 0.005 && !magicBoost }

    /// This chain followed by `next` (an app's effects, then the system output's).
    public func then(_ next: EffectChain) -> EffectChain {
        EffectChain(gain: gain * next.gain, equalizers: equalizers + next.equalizers, balance: min(max(balance + next.balance, -1), 1),
                    magicBoost: magicBoost || next.magicBoost, glide: max(glide, next.glide))
    }

    /// The two channel gains a balance gives: the far side is turned down, the near side stays.
    public static func channelGains(balance: Double) -> (left: Double, right: Double) {
        (min(1, 1 - balance), min(1, 1 + balance))
    }
}

/// What the user set for one app. The defaults leave the app's sound alone.
public struct AppAudioSettings: Codable, Equatable, Sendable {
    /// The slider, 0…1.
    public var volume: Double = 1
    public var muted = false
    /// Volume Overdrive: one of `AudioGain.overdrives`.
    public var overdrive: Double = 1
    public var magicBoost = false
    /// A device UID, an output group (`OutputGroup.prefix` and its id), or nil to follow the system output.
    public var outputUID: String?
    public var eq: EQSettings = .flat
    public var balance: Double = 0
    /// The effect cards on the line, in order.
    public var effects: [EffectKind] = [.overdrive, .equalizer]
    /// Cards switched off: kept with their values, not applied.
    public var bypassed: Set<EffectKind> = []

    public init(volume: Double = 1, muted: Bool = false, overdrive: Double = 1, magicBoost: Bool = false, outputUID: String? = nil,
                eq: EQSettings = .flat, balance: Double = 0) {
        self.volume = volume
        self.muted = muted
        self.overdrive = overdrive
        self.magicBoost = magicBoost
        self.outputUID = outputUID
        self.eq = eq
        self.balance = balance
    }

    private enum CodingKeys: String, CodingKey { case volume, muted, overdrive, boost, magicBoost, outputUID, eq, balance, effects, bypassed }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        volume = min(max(try c.decodeIfPresent(Double.self, forKey: .volume) ?? 1, 0), 1)
        muted = try c.decodeIfPresent(Bool.self, forKey: .muted) ?? false
        // "boost" is what the first version called the overdrive.
        let overdrive = try c.decodeIfPresent(Double.self, forKey: .overdrive) ?? c.decodeIfPresent(Double.self, forKey: .boost) ?? 1
        self.overdrive = min(max(overdrive, 1), AudioGain.maxOverdrive)
        magicBoost = try c.decodeIfPresent(Bool.self, forKey: .magicBoost) ?? false
        outputUID = try c.decodeIfPresent(String.self, forKey: .outputUID)
        eq = try c.decodeIfPresent(EQSettings.self, forKey: .eq) ?? .flat
        balance = min(max(try c.decodeIfPresent(Double.self, forKey: .balance) ?? 0, -1), 1)
        effects = (try? c.decodeIfPresent([String].self, forKey: .effects))?.compactMap(EffectKind.init(rawValue:)) ?? [.overdrive, .equalizer]
        bypassed = Set((try? c.decodeIfPresent([String].self, forKey: .bypassed))?.compactMap(EffectKind.init(rawValue:)) ?? [])
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(volume, forKey: .volume)
        try c.encode(muted, forKey: .muted)
        try c.encode(overdrive, forKey: .overdrive)
        try c.encode(magicBoost, forKey: .magicBoost)
        try c.encodeIfPresent(outputUID, forKey: .outputUID)
        try c.encode(eq, forKey: .eq)
        try c.encode(balance, forKey: .balance)
        try c.encode(effects.map(\.rawValue), forKey: .effects)
        try c.encode(bypassed.map(\.rawValue).sorted(), forKey: .bypassed)
    }

    /// Whether a card is on the line and switched on.
    public func applies(_ effect: EffectKind) -> Bool { effects.contains(effect) && !bypassed.contains(effect) }

    public func chain(muted forcedMute: Bool = false) -> EffectChain {
        let overdrive = applies(.overdrive) ? overdrive : 1
        return EffectChain(gain: AudioGain.amplitude(volume: volume, overdrive: overdrive, muted: muted || forcedMute),
                           equalizers: applies(.equalizer) ? [eq] : [], balance: applies(.balance) ? balance : 0, magicBoost: magicBoost)
    }

    /// True when nothing would change the app's sound or where it goes: it then plays untapped.
    public var isNeutral: Bool { outputUID == nil && chain().isNeutral }

    /// True when also the cards are as they come: nothing worth keeping.
    public var isDefault: Bool { self == AppAudioSettings() }
}

/// The effects of the system output: everything not sent elsewhere goes through them.
public struct SystemEffects: Codable, Equatable, Sendable {
    public var magicBoost = false
    public var eq: EQSettings = .flat
    public var effects: [EffectKind] = [.equalizer]
    public var bypassed: Set<EffectKind> = []

    public init(magicBoost: Bool = false, eq: EQSettings = .flat) {
        self.magicBoost = magicBoost
        self.eq = eq
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        magicBoost = try c.decodeIfPresent(Bool.self, forKey: .magicBoost) ?? false
        eq = try c.decodeIfPresent(EQSettings.self, forKey: .eq) ?? .flat
        effects = (try? c.decodeIfPresent([EffectKind].self, forKey: .effects)) ?? [.equalizer]
        bypassed = (try? c.decodeIfPresent(Set<EffectKind>.self, forKey: .bypassed)) ?? []
    }

    public var chain: EffectChain {
        EffectChain(equalizers: effects.contains(.equalizer) && !bypassed.contains(.equalizer) ? [eq] : [], magicBoost: magicBoost)
    }
}

/// Several output devices that play the same sound at once.
public struct OutputGroup: Codable, Equatable, Identifiable, Sendable {
    /// What an app's output setting starts with when it names a group.
    public static let prefix = "group:"

    public let id: UUID
    public var name: String
    public var deviceUIDs: [String]

    public init(id: UUID = UUID(), name: String, deviceUIDs: [String]) {
        self.id = id
        self.name = name
        self.deviceUIDs = deviceUIDs
    }

    public var reference: String { Self.prefix + id.uuidString }
}

/// What sort of device a transport type is, for its icon and for the AirPlay section of the menu.
public enum AudioDeviceKind: Equatable, Sendable {
    case builtIn, usb, bluetooth, display, airPlay, virtual, aggregate, other

    public init(transport: UInt32) {
        switch transport {
        case kAudioDeviceTransportTypeBuiltIn: self = .builtIn
        case kAudioDeviceTransportTypeUSB: self = .usb
        case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE: self = .bluetooth
        case kAudioDeviceTransportTypeHDMI, kAudioDeviceTransportTypeDisplayPort: self = .display
        case kAudioDeviceTransportTypeAirPlay: self = .airPlay
        case kAudioDeviceTransportTypeVirtual: self = .virtual
        case kAudioDeviceTransportTypeAggregate, kAudioDeviceTransportTypeAutoAggregate: self = .aggregate
        default: self = .other
        }
    }

    /// An SF Symbol for an output (`input` false) or an input.
    public func symbol(input: Bool) -> String {
        switch self {
        case .builtIn: return input ? "mic" : "speaker.wave.2"
        case .usb: return input ? "mic" : "hifispeaker"
        case .bluetooth: return "headphones"
        case .display: return "display"
        case .airPlay: return "airplayaudio"
        case .virtual: return "waveform.circle"
        case .aggregate: return "square.on.square"
        case .other: return input ? "mic" : "speaker.wave.2"
        }
    }
}
