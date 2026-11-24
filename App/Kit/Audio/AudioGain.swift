import Foundation

/// How a volume slider and an overdrive turn into the factor the samples are multiplied by.
public enum AudioGain {
    /// Volume Overdrive steps, as multiples of the app's own level. 1 is "off".
    public static let overdrives: [Double] = [1, 2, 3, 4]
    public static let maxOverdrive: Double = 4
    /// An ordinary change of gain glides over this long instead of clicking.
    public static let defaultGlide: Double = 0.02
    /// The end of a timed mute fades the sound back in over this long.
    public static let fadeIn: Double = 2

    /// The slider (0…1) follows the ear rather than the waveform: half way is about −12 dB.
    public static func amplitude(volume: Double, overdrive: Double, muted: Bool) -> Double {
        guard !muted else { return 0 }
        let v = clamp(volume, 0, 1)
        return v * v * clamp(overdrive, 1, maxOverdrive)
    }

    /// What the line shows: the slider as a percentage.
    public static func percentText(_ volume: Double) -> String {
        "\(Int((clamp(volume, 0, 1) * 100).rounded()))%"
    }

    public static func overdriveText(_ overdrive: Double) -> String { "\(Int(overdrive.rounded()))x" }

    /// Above `knee` the waveform is bent smoothly towards 1 instead of being cut off, so a boosted
    /// app gets louder without crackling.
    public static let knee: Float = 0.89

    @inline(__always) public static func softClip(_ x: Float) -> Float {
        let magnitude = abs(x)
        guard magnitude > knee else { return x }
        let room = 1 - knee
        let bent = knee + room * tanh((magnitude - knee) / room)
        return x < 0 ? -bent : bent
    }

    /// Per-sample smoothing so a changed gain glides over about `seconds`.
    public static func smoothing(sampleRate: Double, seconds: Double) -> Float {
        guard sampleRate > 0, seconds > 0 else { return 1 }
        return Float(1 - exp(-1 / (seconds * sampleRate)))
    }

    private static func clamp(_ value: Double, _ low: Double, _ high: Double) -> Double {
        value.isFinite ? min(max(value, low), high) : low
    }
}

/// Magic Boost: quiet passages are raised towards a steady level, loud ones are left alone. The
/// level is followed block by block, falling quickly and rising slowly so speech does not pump.
public struct MagicBoost: Equatable, Sendable {
    /// The level (RMS) quiet sound is raised towards, about −16 dBFS.
    public static let target: Float = 0.16
    public static let maxGain: Float = 4
    /// Below this the sound is taken as silence and the gain is held, so hiss is not raised.
    public static let floor: Float = 0.002

    public private(set) var level: Float = 0
    public private(set) var gain: Float = 1

    public init() {}

    /// Takes one block's RMS and its length in seconds; returns the gain to reach by the block's end.
    public mutating func next(blockRMS: Float, seconds: Float) -> Float {
        let attack = 1 - exp(-seconds / 0.01), release = 1 - exp(-seconds / 0.3)
        level += (blockRMS - level) * (blockRMS > level ? attack : release)
        guard level > Self.floor else { return gain }
        let wanted = min(max(Self.target / level, 1), Self.maxGain)
        // Down fast (a loud passage starts), up slowly (it ended).
        let rate = wanted < gain ? 1 - exp(-seconds / 0.02) : 1 - exp(-seconds / 1.0)
        gain += (wanted - gain) * rate
        return gain
    }
}
