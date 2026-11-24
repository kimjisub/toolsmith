import Foundation

/// A ten-band graphic equalizer: one gain (dB) per fixed band.
public struct EQSettings: Codable, Equatable, Sendable {
    public static let frequencies: [Double] = [32, 64, 125, 250, 500, 1_000, 2_000, 4_000, 8_000, 16_000]
    public static let gainRange: ClosedRange<Double> = -12...12
    public static let flat = EQSettings(gains: Array(repeating: 0, count: frequencies.count))

    /// One per band, in `frequencies` order, kept inside `gainRange`.
    public private(set) var gains: [Double]

    public init(gains: [Double]) {
        var fitted = gains.prefix(Self.frequencies.count).map(Self.fit)
        fitted += Array(repeating: 0, count: Self.frequencies.count - fitted.count)
        self.gains = fitted
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.init(gains: try container.decode([Double].self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(gains)
    }

    public var isFlat: Bool { gains.allSatisfy { abs($0) < 0.05 } }

    public mutating func setGain(_ gain: Double, band: Int) {
        guard gains.indices.contains(band) else { return }
        gains[band] = Self.fit(gain)
    }

    /// The preset these gains are, if any.
    public var preset: EQPreset? { EQPreset.allCases.first { $0.settings == self } }

    /// Band labels as the sliders show them ("32", "1k", "16k").
    public static func label(band: Int) -> String {
        let hz = frequencies[band]
        return hz >= 1_000 ? "\(Int(hz / 1_000))k" : "\(Int(hz))"
    }

    private static func fit(_ gain: Double) -> Double {
        gain.isFinite ? min(max(gain, gainRange.lowerBound), gainRange.upperBound) : 0
    }
}

public enum EQPreset: String, CaseIterable, Identifiable, Sendable {
    case flat, bassBoost, bassCut, trebleBoost, vocal, loudness, podcast, laptop

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .flat: return "평평하게"
        case .bassBoost: return "저음 강조"
        case .bassCut: return "저음 줄임"
        case .trebleBoost: return "고음 강조"
        case .vocal: return "목소리"
        case .loudness: return "라우드니스"
        case .podcast: return "팟캐스트"
        case .laptop: return "노트북 스피커"
        }
    }

    public var settings: EQSettings {
        switch self {
        case .flat: return .flat
        case .bassBoost: return EQSettings(gains: [6, 5, 4, 2, 0, 0, 0, 0, 0, 0])
        case .bassCut: return EQSettings(gains: [-6, -5, -4, -2, 0, 0, 0, 0, 0, 0])
        case .trebleBoost: return EQSettings(gains: [0, 0, 0, 0, 0, 1, 2, 4, 5, 6])
        case .vocal: return EQSettings(gains: [-3, -2, -1, 0, 2, 3, 3, 2, 0, -1])
        case .loudness: return EQSettings(gains: [5, 4, 2, 0, -1, 0, 0, 2, 4, 5])
        case .podcast: return EQSettings(gains: [-6, -4, -2, 0, 2, 3, 3, 1, -1, -3])
        case .laptop: return EQSettings(gains: [-4, -2, 2, 3, 1, 0, 0, 1, 2, 1])
        }
    }
}

/// One second-order filter section, normalised so a0 is 1 (RBJ Audio EQ Cookbook).
public struct Biquad: Equatable, Sendable {
    public var b0: Double, b1: Double, b2: Double, a1: Double, a2: Double

    public static let identity = Biquad(b0: 1, b1: 0, b2: 0, a1: 0, a2: 0)

    public var isIdentity: Bool { self == .identity }

    /// A peaking bell at `frequency`. Bands too close to Nyquist, or with no gain, pass the signal untouched.
    public static func peaking(frequency: Double, gainDB: Double, q: Double, sampleRate: Double) -> Biquad {
        guard sampleRate > 0, frequency < sampleRate * 0.45, abs(gainDB) >= 0.05, q > 0 else { return .identity }
        let a = pow(10, gainDB / 40)
        let w0 = 2 * Double.pi * frequency / sampleRate
        let alpha = sin(w0) / (2 * q)
        let cosine = cos(w0)
        let a0 = 1 + alpha / a
        return Biquad(b0: (1 + alpha * a) / a0, b1: -2 * cosine / a0, b2: (1 - alpha * a) / a0,
                      a1: -2 * cosine / a0, a2: (1 - alpha / a) / a0)
    }

    /// The filter's gain at `frequency`, in dB.
    public func response(at frequency: Double, sampleRate: Double) -> Double {
        let w = 2 * Double.pi * frequency / sampleRate
        let (c1, s1, c2, s2) = (cos(w), sin(w), cos(2 * w), sin(2 * w))
        let numeratorReal = b0 + b1 * c1 + b2 * c2, numeratorImaginary = -(b1 * s1 + b2 * s2)
        let denominatorReal = 1 + a1 * c1 + a2 * c2, denominatorImaginary = -(a1 * s1 + a2 * s2)
        let power = (numeratorReal * numeratorReal + numeratorImaginary * numeratorImaginary)
            / (denominatorReal * denominatorReal + denominatorImaginary * denominatorImaginary)
        return 10 * log10(power)
    }
}

extension EQSettings {
    public static let q: Double = 1.41

    /// The filter sections for these gains at `sampleRate`, without the bands that do nothing.
    public func sections(sampleRate: Double) -> [Biquad] {
        zip(Self.frequencies, gains)
            .map { Biquad.peaking(frequency: $0, gainDB: $1, q: Self.q, sampleRate: sampleRate) }
            .filter { !$0.isIdentity }
    }
}
