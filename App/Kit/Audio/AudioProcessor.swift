import CoreAudio
import Foundation
import Synchronization
import os

/// What one route does to the samples passing through it: the equalizers, the balance, Magic Boost,
/// the volume and overdrive, then the soft limiter (always last, as the overdrive needs it). `process`
/// runs on the audio device's real-time thread, so it never allocates and never waits: new settings
/// are handed over under a lock the audio thread only tries to take, keeping the previous ones for
/// one more buffer when the lock is busy. It also keeps the latest peak level, for the meters.
public final class AudioProcessor: @unchecked Sendable {
    public static let maxChannels = 16
    /// An app's equalizer followed by the system output's.
    private static let maxSections = EQSettings.frequencies.count * 2

    public let sampleRate: Double

    private let lock: os_unfair_lock_t
    // Written by `set` under the lock.
    private var pending: EffectChain
    private let pendingSections: UnsafeMutablePointer<Biquad>
    private var pendingCount = 0
    private var hasPending = false

    // The audio thread's own copy.
    private var gain: Float
    private var targetGain: Float
    private var smoothing: Float
    private var left: Float = 1, right: Float = 1
    private var boosting = false
    private var boost = MagicBoost()
    private let sections: UnsafeMutablePointer<Biquad>
    private var sectionCount = 0
    /// Two delay values per section per channel (transposed direct form II).
    private let delays: UnsafeMutablePointer<Double>

    private let inputPeakBits = Atomic<UInt32>(0)
    private let outputPeakBits = Atomic<UInt32>(0)

    public init(sampleRate: Double, chain: EffectChain) {
        self.sampleRate = sampleRate
        lock = .allocate(capacity: 1)
        lock.initialize(to: os_unfair_lock())
        pendingSections = .allocate(capacity: Self.maxSections)
        pendingSections.initialize(repeating: .identity, count: Self.maxSections)
        sections = .allocate(capacity: Self.maxSections)
        sections.initialize(repeating: .identity, count: Self.maxSections)
        let delayCount = Self.maxChannels * Self.maxSections * 2
        delays = .allocate(capacity: delayCount)
        delays.initialize(repeating: 0, count: delayCount)
        pending = chain
        gain = Float(chain.gain)
        targetGain = gain
        smoothing = AudioGain.smoothing(sampleRate: sampleRate, seconds: chain.glide)
        let initial = Self.sections(of: chain, sampleRate: sampleRate)
        for (index, section) in initial.enumerated() { sections[index] = section }
        sectionCount = initial.count
        (left, right) = Self.balanceGains(chain)
        boosting = chain.magicBoost
    }

    deinit {
        lock.deinitialize(count: 1)
        lock.deallocate()
        pendingSections.deallocate()
        sections.deallocate()
        delays.deallocate()
    }

    /// The loudest sample of the latest buffer, before and after the effects (0…1).
    public var inputPeak: Float { Float(bitPattern: inputPeakBits.load(ordering: .relaxed)) }
    public var outputPeak: Float { Float(bitPattern: outputPeakBits.load(ordering: .relaxed)) }

    /// From any thread but the audio one.
    public func set(_ chain: EffectChain) {
        let next = Self.sections(of: chain, sampleRate: sampleRate)
        os_unfair_lock_lock(lock)
        pending = chain
        for (index, section) in next.enumerated() { pendingSections[index] = section }
        pendingCount = next.count
        hasPending = true
        os_unfair_lock_unlock(lock)
    }

    /// Only measures (a meter's tap). Real-time safe.
    public func measure(_ list: UnsafePointer<AudioBufferList>) {
        inputPeakBits.store(Self.peak(UnsafeMutablePointer(mutating: list)).bitPattern, ordering: .relaxed)
    }

    /// Runs every buffer of `list` in place. Real-time safe.
    public func process(_ list: UnsafeMutablePointer<AudioBufferList>) {
        takePending()
        inputPeakBits.store(Self.peak(list).bitPattern, ordering: .relaxed)
        let buffers = UnsafeMutableAudioBufferListPointer(list)
        var frames = 0
        var channelBase = 0
        var sum: Float = 0, count = 0
        for buffer in buffers {
            let channels = Int(buffer.mNumberChannels)
            defer { channelBase += channels }
            guard channels > 0, let data = buffer.mData?.assumingMemoryBound(to: Float.self) else { continue }
            frames = Int(buffer.mDataByteSize) / (MemoryLayout<Float>.size * channels)
            for channel in 0..<channels where channelBase + channel < Self.maxChannels {
                equalize(data + channel, frames: frames, stride: channels, channel: channelBase + channel)
            }
            if boosting {
                for index in 0..<(frames * channels) { sum += data[index] * data[index] }
                count += frames * channels
            }
        }
        let boostStart = boost.gain
        let boostEnd = boosting && count > 0 && frames > 0
            ? boost.next(blockRMS: (sum / Float(count)).squareRoot(), seconds: Float(Double(frames) / sampleRate)) : (boosting ? boostStart : 1)
        let start = gain
        var end = start
        let limits = sectionCount > 0 || targetGain > 1 || start > 1 || boosting
        channelBase = 0
        for buffer in buffers {
            let channels = Int(buffer.mNumberChannels)
            defer { channelBase += channels }
            guard channels > 0, let data = buffer.mData?.assumingMemoryBound(to: Float.self) else { continue }
            let count = Int(buffer.mDataByteSize) / (MemoryLayout<Float>.size * channels)
            for channel in 0..<channels {
                // Balance works on the first two channels, the left and right of a stereo pair.
                let side: Float = channelBase + channel == 0 ? left : channelBase + channel == 1 ? right : 1
                end = applyGain(data + channel, frames: count, stride: channels, from: start, side: side,
                                boostFrom: boosting ? boostStart : 1, boostTo: boostEnd, limits: limits)
            }
        }
        gain = end
        outputPeakBits.store(Self.peak(list).bitPattern, ordering: .relaxed)
    }

    private func takePending() {
        guard os_unfair_lock_trylock(lock) else { return }
        if hasPending {
            targetGain = Float(pending.gain)
            smoothing = AudioGain.smoothing(sampleRate: sampleRate, seconds: pending.glide)
            (left, right) = Self.balanceGains(pending)
            if !pending.magicBoost { boost = MagicBoost() }
            boosting = pending.magicBoost
            var changed = pendingCount != sectionCount
            for index in 0..<pendingCount where sections[index] != pendingSections[index] {
                sections[index] = pendingSections[index]
                changed = true
            }
            sectionCount = pendingCount
            // Old delay values belong to the old filters; carried over they would pop.
            if changed { delays.update(repeating: 0, count: Self.maxChannels * Self.maxSections * 2) }
            hasPending = false
        }
        os_unfair_lock_unlock(lock)
    }

    private func equalize(_ samples: UnsafeMutablePointer<Float>, frames: Int, stride: Int, channel: Int) {
        guard sectionCount > 0 else { return }
        for index in 0..<sectionCount {
            let s = sections[index]
            let z = delays + (channel * Self.maxSections + index) * 2
            var z1 = z[0], z2 = z[1]
            var offset = 0
            for _ in 0..<frames {
                let x = Double(samples[offset])
                let y = s.b0 * x + z1
                z1 = s.b1 * x - s.a1 * y + z2
                z2 = s.b2 * x - s.a2 * y
                samples[offset] = Float(y)
                offset += stride
            }
            z[0] = z1
            z[1] = z2
        }
    }

    /// Returns the gain reached at the end, so every channel of a buffer follows the same glide.
    private func applyGain(_ samples: UnsafeMutablePointer<Float>, frames: Int, stride: Int, from start: Float, side: Float,
                           boostFrom: Float, boostTo: Float, limits: Bool) -> Float {
        var g = start
        let target = targetGain
        let gliding = abs(target - start) > 0.0001
        let boostStep = frames > 0 ? (boostTo - boostFrom) / Float(frames) : 0
        var b = boostFrom
        var offset = 0
        for _ in 0..<frames {
            if gliding { g += (target - g) * smoothing }
            b += boostStep
            let y = samples[offset] * (gliding ? g : target) * side * b
            samples[offset] = limits ? AudioGain.softClip(y) : y
            offset += stride
        }
        return gliding ? g : target
    }

    private static func sections(of chain: EffectChain, sampleRate: Double) -> [Biquad] {
        Array(chain.equalizers.flatMap { $0.sections(sampleRate: sampleRate) }.prefix(maxSections))
    }

    private static func balanceGains(_ chain: EffectChain) -> (Float, Float) {
        let gains = EffectChain.channelGains(balance: chain.balance)
        return (Float(gains.left), Float(gains.right))
    }

    private static func peak(_ list: UnsafeMutablePointer<AudioBufferList>) -> Float {
        var peak: Float = 0
        for buffer in UnsafeMutableAudioBufferListPointer(list) {
            guard let data = buffer.mData?.assumingMemoryBound(to: Float.self) else { continue }
            for index in 0..<(Int(buffer.mDataByteSize) / MemoryLayout<Float>.size) { peak = max(peak, abs(data[index])) }
        }
        return peak
    }
}

/// Moves samples from a tap's buffers into an output device's buffers, both 32-bit float.
public enum AudioBufferCopy {
    /// Puts buffer `index` of `list` (one stream of an aggregate device's input, such as the tap's)
    /// into the one-buffer list `single`, so it can be read on its own. False when there is no such
    /// buffer. Real-time safe: nothing is copied but the buffer's description.
    @discardableResult public static func pick(_ index: Int, from list: UnsafePointer<AudioBufferList>, into single: UnsafeMutablePointer<AudioBufferList>) -> Bool {
        let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: list))
        guard buffers.indices.contains(index) else { return false }
        single.pointee.mNumberBuffers = 1
        single.pointee.mBuffers = buffers[index]
        return true
    }

    public static func channelCount(_ list: UnsafePointer<AudioBufferList>) -> Int {
        UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: list)).reduce(0) { $0 + Int($1.mNumberChannels) }
    }

    /// Output channels get the input channel of the same number; ones the input lacks stay silent,
    /// and a mono output gets the input's first two channels averaged. Real-time safe.
    /// With `replicate` (several devices in one route) the input's channels repeat across the output's,
    /// so every stereo device of the group gets the same left and right.
    public static func copy(from input: UnsafePointer<AudioBufferList>, to output: UnsafeMutablePointer<AudioBufferList>, replicate: Bool = false) {
        let source = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
        let inputChannels = channelCount(input)
        var outputChannel = 0
        for buffer in UnsafeMutableAudioBufferListPointer(output) {
            let channels = Int(buffer.mNumberChannels)
            defer { outputChannel += channels }
            guard channels > 0, let data = buffer.mData?.assumingMemoryBound(to: Float.self) else { continue }
            let frames = Int(buffer.mDataByteSize) / (MemoryLayout<Float>.size * channels)
            data.update(repeating: 0, count: frames * channels)
            let mixesToMono = channels == 1 && outputChannel == 0 && UnsafeMutableAudioBufferListPointer(output).count == 1 && inputChannels >= 2
            for channel in 0..<channels {
                if mixesToMono {
                    add(source, channel: 0, into: data, stride: 1, frames: frames, scale: 0.5)
                    add(source, channel: 1, into: data, stride: 1, frames: frames, scale: 0.5)
                } else if replicate, inputChannels > 0 {
                    add(source, channel: (outputChannel + channel) % inputChannels, into: data + channel, stride: channels, frames: frames, scale: 1)
                } else if outputChannel + channel < inputChannels {
                    add(source, channel: outputChannel + channel, into: data + channel, stride: channels, frames: frames, scale: 1)
                }
            }
        }
    }

    private static func add(_ list: UnsafeMutableAudioBufferListPointer, channel: Int, into target: UnsafeMutablePointer<Float>, stride: Int, frames: Int, scale: Float) {
        var base = 0
        for buffer in list {
            let channels = Int(buffer.mNumberChannels)
            defer { base += channels }
            guard channel >= base, channel < base + channels, channels > 0, let data = buffer.mData?.assumingMemoryBound(to: Float.self) else { continue }
            let available = Int(buffer.mDataByteSize) / (MemoryLayout<Float>.size * channels)
            var from = channel - base, to = 0
            for _ in 0..<min(frames, available) {
                target[to] += data[from] * scale
                from += channels
                to += stride
            }
            return
        }
    }
}
