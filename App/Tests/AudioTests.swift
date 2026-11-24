import CoreAudio
import ToolsmithKit
import XCTest

/// Buffers laid out the way a device hands them over: one interleaved buffer, or one per channel.
private final class TestBuffers {
    let list: UnsafeMutableAudioBufferListPointer
    private var storage: [UnsafeMutablePointer<Float>] = []
    let frames: Int

    init(channels: Int, frames: Int, interleaved: Bool, value: (Int, Int) -> Float = { _, _ in 0 }) {
        self.frames = frames
        let bufferCount = interleaved ? 1 : channels
        let perBuffer = interleaved ? channels : 1
        list = AudioBufferList.allocate(maximumBuffers: bufferCount)
        for index in 0..<bufferCount {
            let data = UnsafeMutablePointer<Float>.allocate(capacity: frames * perBuffer)
            for frame in 0..<frames {
                for slot in 0..<perBuffer { data[frame * perBuffer + slot] = value(interleaved ? slot : index, frame) }
            }
            storage.append(data)
            list[index] = AudioBuffer(mNumberChannels: UInt32(perBuffer), mDataByteSize: UInt32(frames * perBuffer * MemoryLayout<Float>.size), mData: data)
        }
    }

    deinit {
        storage.forEach { $0.deallocate() }
        free(list.unsafeMutablePointer)
    }

    func sample(channel: Int, frame: Int) -> Float {
        if list.count == 1 {
            let channels = Int(list[0].mNumberChannels)
            return storage[0][frame * channels + channel]
        }
        return storage[channel][frame]
    }
}

final class AudioGainTests: XCTestCase {
    func testAmplitudeFollowsTheEarAndTheOverdrive() {
        XCTAssertEqual(AudioGain.amplitude(volume: 1, overdrive: 1, muted: false), 1)
        XCTAssertEqual(AudioGain.amplitude(volume: 0.5, overdrive: 1, muted: false), 0.25)
        XCTAssertEqual(AudioGain.amplitude(volume: 1, overdrive: 4, muted: false), 4)
        XCTAssertEqual(AudioGain.amplitude(volume: 1, overdrive: 9, muted: false), 4, "overdrive is capped")
        XCTAssertEqual(AudioGain.amplitude(volume: 0.8, overdrive: 2, muted: true), 0)
    }

    func testTexts() {
        XCTAssertEqual(AudioGain.percentText(1), "100%")
        XCTAssertEqual(AudioGain.percentText(0.694), "69%")
        XCTAssertEqual(AudioGain.overdriveText(3), "3x")
    }

    func testSoftClipPassesQuietSoundAndNeverExceedsFullScale() {
        XCTAssertEqual(AudioGain.softClip(0.5), 0.5)
        XCTAssertEqual(AudioGain.softClip(-0.8), -0.8)
        XCTAssertLessThanOrEqual(AudioGain.softClip(3), 1)
        XCTAssertGreaterThan(AudioGain.softClip(3), 0.95)
        XCTAssertEqual(AudioGain.softClip(-3), -AudioGain.softClip(3))
        XCTAssertGreaterThan(AudioGain.softClip(1.2), AudioGain.softClip(1.0), "louder stays louder")
    }

    func testMagicBoostRaisesQuietSoundButNotLoudOrSilent() {
        var quiet = MagicBoost()
        for _ in 0..<800 { _ = quiet.next(blockRMS: 0.01, seconds: 0.01) }
        XCTAssertEqual(quiet.gain, MagicBoost.maxGain, accuracy: 0.05, "quiet sound reaches the most it may be raised")
        var loud = MagicBoost()
        for _ in 0..<400 { _ = loud.next(blockRMS: 0.4, seconds: 0.01) }
        XCTAssertEqual(loud.gain, 1, accuracy: 0.01)
        var silent = MagicBoost()
        for _ in 0..<400 { _ = silent.next(blockRMS: 0, seconds: 0.01) }
        XCTAssertEqual(silent.gain, 1, "silence is not raised")
    }

    func testMagicBoostComesDownFastWhenItGetsLoud() {
        var boost = MagicBoost()
        for _ in 0..<400 { _ = boost.next(blockRMS: 0.01, seconds: 0.01) }
        for _ in 0..<10 { _ = boost.next(blockRMS: 0.5, seconds: 0.01) }
        XCTAssertLessThan(boost.gain, 1.6, "a tenth of a second after a loud start")
    }
}

final class EqualizerTests: XCTestCase {
    func testGainsAreFittedToTenBandsInRange() {
        let eq = EQSettings(gains: [20, -30, 3])
        XCTAssertEqual(eq.gains.count, 10)
        XCTAssertEqual(Array(eq.gains.prefix(3)), [12, -12, 3])
        XCTAssertEqual(Array(eq.gains.suffix(7)), Array(repeating: 0, count: 7))
    }

    func testFlatAndPresets() {
        XCTAssertTrue(EQSettings.flat.isFlat)
        XCTAssertEqual(EQSettings.flat.preset, .flat)
        XCTAssertEqual(EQPreset.bassBoost.settings.preset, .bassBoost)
        var eq = EQPreset.bassBoost.settings
        eq.setGain(1, band: 9)
        XCTAssertNil(eq.preset)
        XCTAssertEqual(EQSettings.label(band: 0), "32")
        XCTAssertEqual(EQSettings.label(band: 9), "16k")
    }

    func testPeakingFilterReachesItsGainAtTheCentre() {
        let filter = Biquad.peaking(frequency: 1_000, gainDB: 6, q: EQSettings.q, sampleRate: 48_000)
        XCTAssertEqual(filter.response(at: 1_000, sampleRate: 48_000), 6, accuracy: 0.01)
        XCTAssertEqual(filter.response(at: 20, sampleRate: 48_000), 0, accuracy: 0.1)
        XCTAssertTrue(Biquad.peaking(frequency: 1_000, gainDB: 0, q: 1, sampleRate: 48_000).isIdentity)
        XCTAssertTrue(Biquad.peaking(frequency: 16_000, gainDB: 6, q: 1, sampleRate: 22_050).isIdentity, "too close to Nyquist")
    }

    func testOnlyBandsThatDoSomethingBecomeSections() {
        XCTAssertTrue(EQSettings.flat.sections(sampleRate: 48_000).isEmpty)
        XCTAssertEqual(EQSettings(gains: [3, 0, 0, 0, 0, 0, 0, 0, 0, -3]).sections(sampleRate: 48_000).count, 2)
    }

    func testDecodesFromAPlainList() throws {
        let eq = try JSONDecoder().decode(EQSettings.self, from: Data("[1,2,3]".utf8))
        XCTAssertEqual(Array(eq.gains.prefix(3)), [1, 2, 3])
        XCTAssertEqual(try JSONDecoder().decode(EQSettings.self, from: JSONEncoder().encode(eq)), eq)
    }
}

final class AudioProcessorTests: XCTestCase {
    func testSteadyGainScalesEveryChannel() {
        let processor = AudioProcessor(sampleRate: 48_000, chain: EffectChain(gain: 0.5))
        let buffers = TestBuffers(channels: 2, frames: 64, interleaved: true) { channel, _ in channel == 0 ? 0.4 : -0.2 }
        processor.process(buffers.list.unsafeMutablePointer)
        XCTAssertEqual(buffers.sample(channel: 0, frame: 10), 0.2, accuracy: 1e-6)
        XCTAssertEqual(buffers.sample(channel: 1, frame: 63), -0.1, accuracy: 1e-6)
        XCTAssertEqual(processor.inputPeak, 0.4, accuracy: 1e-6)
        XCTAssertEqual(processor.outputPeak, 0.2, accuracy: 1e-6)
    }

    func testChangedGainGlidesInsteadOfJumping() {
        let processor = AudioProcessor(sampleRate: 48_000, chain: EffectChain())
        processor.set(EffectChain(gain: 0))
        let buffers = TestBuffers(channels: 1, frames: 4_800, interleaved: false) { _, _ in 0.5 }
        processor.process(buffers.list.unsafeMutablePointer)
        XCTAssertGreaterThan(buffers.sample(channel: 0, frame: 0), 0.45, "the first sample is still near the old level")
        XCTAssertLessThan(buffers.sample(channel: 0, frame: 4_799), 0.01, "a tenth of a second later it is silent")
    }

    func testFadeInTakesAsLongAsTheChainSays() {
        let processor = AudioProcessor(sampleRate: 48_000, chain: EffectChain(gain: 0))
        processor.set(EffectChain(gain: 1, glide: AudioGain.fadeIn))
        let buffers = TestBuffers(channels: 1, frames: 4_800, interleaved: true) { _, _ in 0.5 }
        processor.process(buffers.list.unsafeMutablePointer)
        XCTAssertLessThan(buffers.sample(channel: 0, frame: 4_799), 0.05, "a tenth of a second into a two-second fade")
    }

    func testSeparateChannelBuffersFollowTheSameGlide() {
        let processor = AudioProcessor(sampleRate: 48_000, chain: EffectChain())
        processor.set(EffectChain(gain: 0.2))
        let buffers = TestBuffers(channels: 2, frames: 256, interleaved: false) { _, _ in 1 }
        processor.process(buffers.list.unsafeMutablePointer)
        for frame in [0, 100, 255] {
            XCTAssertEqual(buffers.sample(channel: 0, frame: frame), buffers.sample(channel: 1, frame: frame), accuracy: 1e-6)
        }
    }

    func testOverdrivenSoundIsLimitedAtFullScale() {
        let processor = AudioProcessor(sampleRate: 48_000, chain: EffectChain(gain: 4))
        let buffers = TestBuffers(channels: 1, frames: 32, interleaved: true) { _, _ in 0.9 }
        processor.process(buffers.list.unsafeMutablePointer)
        XCTAssertLessThanOrEqual(buffers.sample(channel: 0, frame: 5), 1)
        XCTAssertGreaterThan(buffers.sample(channel: 0, frame: 5), 0.95)
    }

    func testBalanceTurnsDownTheFarSide() {
        let processor = AudioProcessor(sampleRate: 48_000, chain: EffectChain(balance: 0.5))
        let buffers = TestBuffers(channels: 2, frames: 16, interleaved: true) { _, _ in 0.4 }
        processor.process(buffers.list.unsafeMutablePointer)
        XCTAssertEqual(buffers.sample(channel: 0, frame: 3), 0.2, accuracy: 1e-6)
        XCTAssertEqual(buffers.sample(channel: 1, frame: 3), 0.4, accuracy: 1e-6)
    }

    private func peakOfSine(_ chain: EffectChain, amplitude: Double = 0.1, seconds: Double = 0.2) -> Float {
        let rate = 48_000.0
        let processor = AudioProcessor(sampleRate: rate, chain: chain)
        var last: Float = 0
        // Buffers of 480 frames, as a device would hand them over; the last one is measured.
        let blocks = Int(seconds * rate / 480)
        for block in 0..<blocks {
            let buffers = TestBuffers(channels: 1, frames: 480, interleaved: true) { _, frame in
                Float(amplitude * sin(2 * Double.pi * 1_000 * Double(block * 480 + frame) / rate))
            }
            processor.process(buffers.list.unsafeMutablePointer)
            last = (0..<480).map { abs(buffers.sample(channel: 0, frame: $0)) }.max() ?? 0
        }
        return last
    }

    func testEqualizerLiftsItsBand() {
        var lifted = EQSettings.flat
        lifted.setGain(12, band: 5)
        XCTAssertEqual(peakOfSine(EffectChain()), 0.1, accuracy: 0.001)
        XCTAssertEqual(Double(peakOfSine(EffectChain(equalizers: [lifted]))), 0.1 * pow(10, 12.0 / 20), accuracy: 0.02)
    }

    func testTwoEqualizersAddUp() {
        var half = EQSettings.flat
        half.setGain(6, band: 5)
        XCTAssertEqual(Double(peakOfSine(EffectChain(equalizers: [half, half]))), 0.1 * pow(10, 12.0 / 20), accuracy: 0.03)
    }

    func testMagicBoostRaisesAQuietTone() {
        let boosted = peakOfSine(EffectChain(magicBoost: true), amplitude: 0.01, seconds: 4)
        XCTAssertGreaterThan(boosted, 0.03)
        XCTAssertLessThanOrEqual(boosted, 0.041)
    }

    func testMeasureOnlyReadsTheLevel() {
        let processor = AudioProcessor(sampleRate: 48_000, chain: EffectChain())
        let buffers = TestBuffers(channels: 2, frames: 16, interleaved: true) { _, frame in frame == 7 ? -0.6 : 0.1 }
        processor.measure(buffers.list.unsafePointer)
        XCTAssertEqual(processor.inputPeak, 0.6, accuracy: 1e-6)
        XCTAssertEqual(buffers.sample(channel: 0, frame: 7), -0.6)
    }
}

final class AudioBufferCopyTests: XCTestCase {
    func testStereoToStereoAcrossLayouts() {
        let input = TestBuffers(channels: 2, frames: 8, interleaved: true) { channel, frame in Float(channel * 100 + frame) }
        let output = TestBuffers(channels: 2, frames: 8, interleaved: false, value: { _, _ in 9 })
        AudioBufferCopy.copy(from: input.list.unsafePointer, to: output.list.unsafeMutablePointer)
        XCTAssertEqual(output.sample(channel: 0, frame: 3), 3)
        XCTAssertEqual(output.sample(channel: 1, frame: 7), 107)
    }

    func testMonoOutputGetsTheAverage() {
        let input = TestBuffers(channels: 2, frames: 4, interleaved: true) { channel, _ in channel == 0 ? 1 : 0 }
        let output = TestBuffers(channels: 1, frames: 4, interleaved: true)
        AudioBufferCopy.copy(from: input.list.unsafePointer, to: output.list.unsafeMutablePointer)
        XCTAssertEqual(output.sample(channel: 0, frame: 2), 0.5)
    }

    func testPickTakesOneStreamOfAnAggregate() {
        // An aggregate's input: the output device's own loopback first, then the tap.
        let both = TestBuffers(channels: 2, frames: 4, interleaved: false) { channel, _ in channel == 0 ? 0.9 : 0.3 }
        let single = AudioBufferList.allocate(maximumBuffers: 1)
        defer { free(single.unsafeMutablePointer) }
        XCTAssertTrue(AudioBufferCopy.pick(1, from: both.list.unsafePointer, into: single.unsafeMutablePointer))
        XCTAssertEqual(single.count, 1)
        XCTAssertEqual(single[0].mData?.assumingMemoryBound(to: Float.self)[0], 0.3)
        XCTAssertFalse(AudioBufferCopy.pick(2, from: both.list.unsafePointer, into: single.unsafeMutablePointer))
    }

    func testGroupsRepeatTheStereoPairOnEveryDevice() {
        let input = TestBuffers(channels: 2, frames: 4, interleaved: true) { channel, _ in channel == 0 ? 0.1 : 0.2 }
        let output = TestBuffers(channels: 4, frames: 4, interleaved: false)
        AudioBufferCopy.copy(from: input.list.unsafePointer, to: output.list.unsafeMutablePointer, replicate: true)
        XCTAssertEqual([0, 1, 2, 3].map { output.sample(channel: $0, frame: 1) }, [0.1, 0.2, 0.1, 0.2])
    }

    func testExtraOutputChannelsAreSilentAndShortInputLeavesTheRestSilent() {
        let input = TestBuffers(channels: 2, frames: 4, interleaved: true) { _, _ in 1 }
        let output = TestBuffers(channels: 4, frames: 6, interleaved: true, value: { _, _ in 9 })
        AudioBufferCopy.copy(from: input.list.unsafePointer, to: output.list.unsafeMutablePointer)
        XCTAssertEqual(output.sample(channel: 1, frame: 0), 1)
        XCTAssertEqual(output.sample(channel: 2, frame: 0), 0)
        XCTAssertEqual(output.sample(channel: 0, frame: 5), 0)
        XCTAssertEqual(AudioBufferCopy.channelCount(output.list.unsafePointer), 4)
    }
}

final class AudioAppsTests: XCTestCase {
    func testGroupsByAppSkippingOurselves() {
        let entries = [
            AudioProcessEntry(objectID: 11, pid: 100, bundleID: "com.google.Chrome", executablePath: "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome", isPlaying: false),
            AudioProcessEntry(objectID: 12, pid: 101, bundleID: "com.google.Chrome.helper", executablePath: "/Applications/Google Chrome.app/Contents/Frameworks/X.framework/Helpers/Google Chrome Helper.app/Contents/MacOS/Google Chrome Helper", isPlaying: true),
            AudioProcessEntry(objectID: 13, pid: 200, bundleID: nil, executablePath: "/usr/bin/afplay", isPlaying: true),
            AudioProcessEntry(objectID: 14, pid: 300, bundleID: AppIdentity.bundleID, executablePath: "/Applications/\(AppIdentity.name).app/Contents/MacOS/\(AppIdentity.name)", isPlaying: true),
            AudioProcessEntry(objectID: 15, pid: 400, bundleID: nil, executablePath: nil, isPlaying: true),
            AudioProcessEntry(objectID: 16, pid: 500, bundleID: "", executablePath: nil, isPlaying: true),
        ]
        let groups = AudioApps.group(entries, ownPID: 300) { $0 == "/Applications/Google Chrome.app" ? "com.google.Chrome" : nil }
        XCTAssertEqual(groups.map(\.key), ["com.google.Chrome", "path:/usr/bin/afplay"])
        XCTAssertEqual(groups[0].processIDs, [11, 12])
        XCTAssertTrue(groups[0].isPlaying)
        XCTAssertEqual(groups[0].appPath, "/Applications/Google Chrome.app")
    }

    func testRowsPutFavoritesFirstThenPlayingThenRecent() {
        let now = Date(timeIntervalSince1970: 1_000)
        let groups = [
            AudioAppGroup(key: "b.quiet", appPath: nil, processIDs: [1], isPlaying: false),
            AudioAppGroup(key: "c.playing", appPath: nil, processIDs: [2], isPlaying: true),
            AudioAppGroup(key: "a.playing", appPath: nil, processIDs: [3], isPlaying: true),
            AudioAppGroup(key: "d.recent", appPath: nil, processIDs: [4], isPlaying: false),
            AudioAppGroup(key: "e.configured", appPath: nil, processIDs: [5], isPlaying: false),
        ]
        let rows = AudioApps.rows(groups: groups, favorites: ["z.notRunning", "c.playing"], configured: ["e.configured"],
                                  lastHeard: ["d.recent": now.addingTimeInterval(-30), "b.quiet": now.addingTimeInterval(-90)],
                                  now: now, name: { $0 })
        XCTAssertEqual(rows.map(\.key), ["z.notRunning", "c.playing", "a.playing", "d.recent", "e.configured"])
        XCTAssertNil(rows[0].group)
        XCTAssertTrue(rows[1].isFavorite && rows[1].isPlaying)
        XCTAssertTrue(rows[3].isRecent)
        XCTAssertFalse(rows[4].isRecent)
    }

    func testRememberKeepsOnlyTheWindow() {
        let now = Date(timeIntervalSince1970: 1_000)
        var heard: [String: Date] = ["old": now.addingTimeInterval(-61), "kept": now.addingTimeInterval(-10)]
        AudioApps.remember([AudioAppGroup(key: "new", appPath: nil, processIDs: [1], isPlaying: true)], in: &heard, now: now)
        XCTAssertEqual(Set(heard.keys), ["kept", "new"])
    }
}

final class AudioRoutesTests: XCTestCase {
    private let chrome = AudioAppGroup(key: "chrome", appPath: nil, processIDs: [12, 11], isPlaying: true)
    private let music = AudioAppGroup(key: "music", appPath: nil, processIDs: [20], isPlaying: true)
    private let quiet = AudioAppGroup(key: "quiet", appPath: nil, processIDs: [30], isPlaying: false)

    private func plan(_ groups: [AudioAppGroup], _ settings: [String: AppAudioSettings], system: SystemEffects = SystemEffects(), outputGroups: [OutputGroup] = [],
                      connected: Set<String> = ["speakers", "headphones"], own: UInt32? = 5, muted: Set<String> = []) -> [String: RoutePlan] {
        AudioRoutes.plan(groups: groups, settings: settings, system: system, outputGroups: outputGroups, defaultOutputUID: "speakers",
                         connected: connected, ownProcessID: own, muted: muted)
    }

    func testUntouchedAppsGetNoRoute() {
        var cardsOnly = AppAudioSettings()
        cardsOnly.effects = [.balance]
        XCTAssertTrue(plan([chrome, music], ["music": AppAudioSettings(), "chrome": cardsOnly]).isEmpty)
    }

    func testRedirectedAppGoesToItsDeviceAndBackToTheSystemWhenItIsGone() {
        let settings = ["chrome": AppAudioSettings(volume: 0.5, outputUID: "headphones")]
        let plugged = plan([chrome], settings)
        XCTAssertEqual(plugged["chrome"]?.structure, RouteStructure(source: .processes([11, 12]), outputUIDs: ["headphones"]))
        XCTAssertEqual(plugged["chrome"]?.chain.gain, 0.25)
        XCTAssertEqual(plan([chrome], settings, connected: ["speakers"])["chrome"]?.structure.outputUIDs, ["speakers"])
    }

    func testAnOutputGroupPlaysOnItsConnectedDevices() {
        let group = OutputGroup(name: "둘", deviceUIDs: ["headphones", "speakers", "gone"])
        let plans = plan([music], ["music": AppAudioSettings(outputUID: group.reference)], outputGroups: [group])
        XCTAssertEqual(plans["music"]?.structure.outputUIDs, ["headphones", "speakers"])
    }

    func testSystemEffectsRouteLeavesOutOurselvesAndRoutedApps() {
        let system = SystemEffects(magicBoost: true, eq: EQPreset.vocal.settings)
        let plans = plan([chrome, music], ["chrome": AppAudioSettings(volume: 0.5), "music": AppAudioSettings(outputUID: "headphones")], system: system)
        XCTAssertEqual(plans[AudioRoutes.systemKey]?.structure, RouteStructure(source: .everythingExcept([5, 11, 12, 20]), outputUIDs: ["speakers"]))
        XCTAssertEqual(plans["chrome"]?.chain.equalizers.count, 1, "sent to the system output, it takes the system's effects itself")
        XCTAssertEqual(plans["chrome"]?.chain.magicBoost, true)
        XCTAssertEqual(plans["music"]?.chain.equalizers.count, 0, "sent elsewhere, it does not")
    }

    func testNoSystemRouteWithoutKnowingOurOwnProcess() {
        XCTAssertNil(plan([], [:], system: SystemEffects(magicBoost: true), own: nil)[AudioRoutes.systemKey])
        XCTAssertNil(plan([], [:])[AudioRoutes.systemKey], "nothing set, nothing to run")
    }

    func testATimedMuteRoutesAnUntouchedApp() {
        XCTAssertEqual(plan([music], [:], muted: ["music"])["music"]?.chain.gain, 0)
    }

    func testBypassedEffectsDoNothing() {
        var settings = AppAudioSettings(overdrive: 3, eq: EQPreset.bassBoost.settings)
        settings.bypassed = [.overdrive, .equalizer]
        XCTAssertTrue(settings.isNeutral)
        XCTAssertFalse(settings.isDefault)
    }

    func testMetersForPlayingAppsWithoutARoute() {
        let meters = AudioRoutes.meterPlans(groups: [chrome, music, quiet], routed: ["music"])
        XCTAssertEqual(Set(meters.keys), [AudioRoutes.outputMeterKey, AudioRoutes.meterPrefix + "chrome"])
        XCTAssertTrue(meters[AudioRoutes.outputMeterKey]?.structure.isMeter ?? false)
    }

    func testChangesRebuildOnlyWhatChangedShape() {
        let a = RouteStructure(source: .processes([1]), outputUIDs: ["x"])
        let running = ["keep": a, "move": a, "gone": a]
        let desired = [
            "keep": RoutePlan(structure: a, chain: EffectChain(gain: 0.5)),
            "move": RoutePlan(structure: RouteStructure(source: .processes([1]), outputUIDs: ["y"]), chain: EffectChain()),
            "new": RoutePlan(structure: a, chain: EffectChain()),
        ]
        let changes = AudioRoutes.changes(running: running, desired: desired)
        XCTAssertEqual(changes.stop, ["gone", "move"])
        XCTAssertEqual(changes.start, ["move", "new"])
        XCTAssertEqual(changes.update, ["keep"])
    }

    func testDriftIsCompensatedExceptForBluetoothAndVirtualOutputs() {
        XCTAssertTrue(AudioRoutes.compensatesDrift(outputTransport: kAudioDeviceTransportTypeBuiltIn))
        XCTAssertTrue(AudioRoutes.compensatesDrift(outputTransport: kAudioDeviceTransportTypeUSB))
        XCTAssertFalse(AudioRoutes.compensatesDrift(outputTransport: kAudioDeviceTransportTypeBluetooth))
        XCTAssertFalse(AudioRoutes.compensatesDrift(outputTransport: kAudioDeviceTransportTypeVirtual))
    }

    func testChainsFollowOneAnother() {
        let app = EffectChain(gain: 0.5, equalizers: [EQPreset.vocal.settings], balance: -0.5)
        let system = EffectChain(gain: 2, equalizers: [EQPreset.bassBoost.settings], magicBoost: true)
        let both = app.then(system)
        XCTAssertEqual(both.gain, 1)
        XCTAssertEqual(both.equalizers.count, 2)
        XCTAssertTrue(both.magicBoost)
        XCTAssertTrue(EffectChain(equalizers: [.flat]).isNeutral, "a flat equalizer is no equalizer")
        XCTAssertEqual(EffectChain.channelGains(balance: -1).right, 0)
        XCTAssertEqual(EffectChain.channelGains(balance: 0).left, 1)
    }

    func testSettingsDecodeLenientlyAndFromTheFirstVersion() throws {
        let decoded = try JSONDecoder().decode(AppAudioSettings.self, from: Data(#"{"volume": 3, "boost": 2, "effects": ["equalizer", "nonsense"]}"#.utf8))
        XCTAssertEqual(decoded.volume, 1)
        XCTAssertEqual(decoded.overdrive, 2, "the first version's boost is the overdrive")
        XCTAssertEqual(decoded.effects, [.equalizer])
        let roundTrip = try JSONDecoder().decode(AppAudioSettings.self, from: JSONEncoder().encode(decoded))
        XCTAssertEqual(roundTrip, decoded)
    }

    func testDeviceKinds() {
        XCTAssertEqual(AudioDeviceKind(transport: kAudioDeviceTransportTypeAirPlay), .airPlay)
        XCTAssertEqual(AudioDeviceKind(transport: kAudioDeviceTransportTypeBluetoothLE), .bluetooth)
        XCTAssertEqual(AudioDeviceKind(transport: kAudioDeviceTransportTypeBuiltIn).symbol(input: true), "mic")
    }
}

final class AudioConfigTests: XCTestCase {
    private func temporaryFile() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("audio-tests-\(UUID().uuidString)", isDirectory: true).appendingPathComponent("audio.json")
    }

    func testDefaultsAreNotKeptAndFavoritesDoNotRepeat() {
        var configuration = AudioConfiguration()
        configuration.apps = ["a": AppAudioSettings(), "b": AppAudioSettings(volume: 0.3)]
        configuration.favorites = ["x", "y", "x"]
        let normalized = configuration.normalized()
        XCTAssertEqual(Array(normalized.apps.keys), ["b"])
        XCTAssertEqual(normalized.favorites, ["x", "y"])
    }

    func testRemovingAGroupSendsItsAppsBackToTheSystemOutput() {
        var configuration = AudioConfiguration()
        let group = OutputGroup(name: "둘", deviceUIDs: ["a", "b"])
        configuration.outputGroups = [group, OutputGroup(name: "빈", deviceUIDs: [])]
        configuration.apps = ["music": AppAudioSettings(volume: 0.5, outputUID: group.reference)]
        XCTAssertEqual(configuration.normalized().outputGroups.map(\.name), ["둘"])
        configuration.outputGroups = []
        XCTAssertNil(configuration.normalized().apps["music"]?.outputUID)
        XCTAssertTrue(AudioConfiguration().effectsFollowOutput, "alerts follow the system output unless told otherwise")
    }

    func testFavoritesToggleAndMove() {
        var configuration = AudioConfiguration()
        configuration.toggleFavorite("a")
        configuration.toggleFavorite("b")
        configuration.moveFavorite("b", by: -1)
        XCTAssertEqual(configuration.favorites, ["b", "a"])
        configuration.moveFavorite("b", by: -1)
        XCTAssertEqual(configuration.favorites, ["b", "a"])
        configuration.toggleFavorite("b")
        XCTAssertEqual(configuration.favorites, ["a"])
    }

    func testStoreKeepsSettingsAndQuickConfigsAcrossLaunches() {
        let url = temporaryFile()
        let store = AudioConfigStore(fileURL: url)
        store.updateApp("music") { $0.volume = 0.4 }
        store.update { $0.favorites = ["music"] }
        let saved = store.saveQuickConfig(name: "  회의  ", system: SystemAudioState(outputUID: "speakers", outputVolume: 0.5))
        XCTAssertEqual(saved?.name, "회의")
        XCTAssertNil(store.saveQuickConfig(name: " ", system: SystemAudioState()))
        store.updateApp("music") { $0.volume = 1 }
        XCTAssertNil(store.configuration.apps["music"], "back to the default, nothing is kept")

        let reopened = AudioConfigStore(fileURL: url)
        XCTAssertEqual(reopened.configuration.quickConfigs.count, 1)
        XCTAssertEqual(reopened.configuration.quickConfigs[0].apps["music"]?.volume, 0.4)
        XCTAssertEqual(reopened.configuration.quickConfigs[0].system.outputUID, "speakers")

        // Saving under the same name replaces it.
        reopened.saveQuickConfig(name: "회의", system: SystemAudioState())
        XCTAssertEqual(reopened.configuration.quickConfigs.count, 1)
        reopened.update { $0.apply(reopened.configuration.quickConfigs[0]) }
        XCTAssertEqual(reopened.configuration.favorites, ["music"])
        reopened.removeQuickConfig(reopened.configuration.quickConfigs[0].id)
        XCTAssertTrue(reopened.configuration.quickConfigs.isEmpty)
    }

    func testUnreadableFileIsMovedAsideNotOverwritten() throws {
        let url = temporaryFile()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: url)
        let store = AudioConfigStore(fileURL: url)
        XCTAssertTrue(store.loadFailed)
        let aside = url.deletingLastPathComponent().appendingPathComponent("audio.broken.json")
        XCTAssertEqual(try String(contentsOf: aside, encoding: .utf8), "not json")
    }
}
