#if TOOLSMITH_DEV
import AVFoundation
import CoreAudio
import Foundation
import ToolsmithKit

/// Development aid: a sine wave played on one device by a process of its own (this executable run
/// with `--play-tone`), so there is an app to tap that is not this one.
enum TonePlayer {
    private final class Phase: @unchecked Sendable { var value = 0.0 }

    static func run(uid: String, frequency: Double, amplitude: Double, seconds: Double) -> Never {
        guard let device = SystemAudio.devices().first(where: { $0.uid == uid }) else { exit(2) }
        let rate = AudioProperty.value(device.id, AudioProperty.address(kAudioDevicePropertyNominalSampleRate), initial: Float64(48_000)) ?? 48_000
        let step = 2 * Double.pi * frequency / rate
        let phase = Phase()
        var proc: AudioDeviceIOProcID?
        AudioDeviceCreateIOProcIDWithBlock(&proc, device.id, nil) { _, _, _, output, _ in
            let buffers = UnsafeMutableAudioBufferListPointer(output)
            let start = phase.value
            var end = start
            for buffer in buffers {
                let channels = Int(buffer.mNumberChannels)
                guard channels > 0, let data = buffer.mData?.assumingMemoryBound(to: Float.self) else { continue }
                let frames = Int(buffer.mDataByteSize) / (MemoryLayout<Float>.size * channels)
                var p = start
                for frame in 0..<frames {
                    let sample = Float(amplitude * sin(p))
                    for channel in 0..<channels { data[frame * channels + channel] = sample }
                    p += step
                }
                end = p
            }
            phase.value = end.truncatingRemainder(dividingBy: 2 * Double.pi)
        }
        guard let proc, AudioDeviceStart(device.id, proc) == noErr else { exit(3) }
        Thread.sleep(forTimeInterval: seconds)
        exit(0)
    }
}

/// Development aid: checks the routes on real sound, without ears. A tone process plays into
/// BlackHole; this app listens to BlackHole's input (its loopback) and compares the level with and
/// without each route: volume, mute, overdrive, equalizer, balance, Magic Boost, sending the app
/// elsewhere (nothing must be left on BlackHole: the original output is muted while tapped), and an
/// output group. Needs the microphone (to read BlackHole) and System Audio Recording (the tap).
@MainActor final class AudioSelfTest {
    private final class Recorder: @unchecked Sendable {
        private let lock = NSLock()
        private var sums = [Double](repeating: 0, count: 2)
        private var count = 0

        func add(_ list: UnsafePointer<AudioBufferList>) {
            lock.lock()
            defer { lock.unlock() }
            var channelBase = 0
            for buffer in UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: list)) {
                let channels = Int(buffer.mNumberChannels)
                defer { channelBase += channels }
                guard channels > 0, let data = buffer.mData?.assumingMemoryBound(to: Float.self) else { continue }
                let frames = Int(buffer.mDataByteSize) / (MemoryLayout<Float>.size * channels)
                for channel in 0..<channels where channelBase + channel < 2 {
                    var sum = 0.0
                    for frame in 0..<frames { let x = Double(data[frame * channels + channel]); sum += x * x }
                    sums[channelBase + channel] += sum
                }
                if channelBase == 0 { count += frames }
            }
        }

        func reset() { lock.withLock { sums = [0, 0]; count = 0 } }

        /// RMS of the left and right channels since the last reset.
        func rms() -> (Double, Double) {
            lock.withLock { count == 0 ? (0, 0) : ((sums[0] / Double(count)).squareRoot(), (sums[1] / Double(count)).squareRoot()) }
        }
    }

    struct Row {
        let name: String
        let expected: String
        let left: Double
        let right: Double
        let baseline: Double
        let pass: Bool
    }

    private let resultURL: URL
    private var lines: [String] = []

    init(resultPath: String) {
        resultURL = URL(fileURLWithPath: resultPath)
    }

    private func log(_ line: String) {
        lines.append(line)
        try? lines.joined(separator: "\n").write(to: resultURL, atomically: true, encoding: .utf8)
    }

    private func wait(_ seconds: Double) async { try? await Task.sleep(for: .seconds(seconds)) }

    func run() async {
        log("# Audio route self-test \(Date())")
        let devices = SystemAudio.devices()
        guard let blackHole = devices.first(where: { $0.uid == "BlackHole2ch_UID" }) else { return finish("BlackHole 2ch is not installed") }
        // Somewhere else to send the tone: a silent virtual device if there is one, else the built-in
        // speakers, then at a tenth of the level so the Mac only whispers for a second or two.
        let virtualSink = devices.first { $0.hasOutput && $0.uid != blackHole.uid && AudioDeviceKind(transport: $0.transport) == .virtual }
        let sink = virtualSink ?? devices.first { $0.hasOutput && AudioDeviceKind(transport: $0.transport) == .builtIn }
        let sinkGain = virtualSink == nil ? 0.1 : 1.0

        log("Asking for microphone access (to read the BlackHole input)")
        guard await AVCaptureDevice.requestAccess(for: .audio) else { return finish("No microphone access, so BlackHole cannot be read") }

        // A muted BlackHole loops back silence. Unmuted for the test, and left as it was afterwards.
        let wasMuted = SystemAudio.isMuted(blackHole.id, .output) ?? false
        if wasMuted {
            SystemAudio.setMuted(blackHole.id, .output, false)
            log("BlackHole output is muted; unmuting it for the test only")
        }
        defer { if wasMuted { SystemAudio.setMuted(blackHole.id, .output, true) } }

        let recorder = Recorder()
        var inputProc: AudioDeviceIOProcID?
        AudioDeviceCreateIOProcIDWithBlock(&inputProc, blackHole.id, nil) { _, input, _, _, _ in recorder.add(input) }
        guard let inputProc, AudioDeviceStart(blackHole.id, inputProc) == noErr else { return finish("Could not start the BlackHole input") }
        defer {
            AudioDeviceStop(blackHole.id, inputProc)
            AudioDeviceDestroyIOProcID(blackHole.id, inputProc)
        }

        func measure() async -> (Double, Double) {
            recorder.reset()
            await wait(0.8)
            return recorder.rms()
        }

        var tone = startTone(amplitude: 0.2)
        defer { tone?.terminate() }
        await wait(1.5)
        guard let toneProcess = tone.flatMap({ child in SystemAudio.processes().first { $0.pid == child.processIdentifier } }) else {
            return finish("The audio system has no object for the test tone process")
        }
        let base = await measure()
        log("Baseline (no route): L \(fmt(base.0)) R \(fmt(base.1))")
        guard base.0 > 0.05 else { return finish("The test tone does not reach BlackHole (check microphone access)") }

        // The first tap is where macOS asks for System Audio Recording; until it is allowed the tap is silent.
        log("Waiting for system audio recording permission (up to 15 minutes)")
        let source = TapSource.processes([toneProcess.objectID])
        do {
            let probe = try TapRoute(plan: RoutePlan(structure: RouteStructure(source: source, outputUIDs: [blackHole.uid]), chain: EffectChain()), outputs: [blackHole], clock: nil)
            var waited = 0.0
            while probe.processor.inputPeak < 0.01, waited < 900 {
                await wait(0.5)
                waited += 0.5
            }
            probe.stop()
            guard waited < 900 else { return finish("No sound reaches the tap (check system audio recording permission)") }
            log("Permission confirmed (\(Int(waited)) s)")
        } catch {
            return finish("Could not create the tap: \((error as? TapRouteError)?.message ?? "\(error)")")
        }
        await wait(0.6)

        var rows: [Row] = []
        func check(_ name: String, expected: String, outputs: [AudioDevice], chain: EffectChain, settle: Double = 1.2,
                   reference: (Double, Double), pass: (Double, Double) -> Bool) async {
            do {
                let route = try TapRoute(plan: RoutePlan(structure: RouteStructure(source: source, outputUIDs: outputs.map(\.uid)), chain: chain), outputs: outputs, clock: nil)
                await wait(settle)
                let level = await measure()
                route.stop()
                let left = level.0 / reference.0, right = level.1 / reference.1
                rows.append(Row(name: name, expected: expected, left: left, right: right, baseline: reference.0, pass: pass(left, right)))
            } catch {
                rows.append(Row(name: name, expected: "route failed: \((error as? TapRouteError)?.message ?? "\(error)")", left: .nan, right: .nan, baseline: reference.0, pass: false))
            }
            await wait(0.6)
        }
        func near(_ value: Double, _ target: Double, _ tolerance: Double) -> Bool { abs(value - target) <= tolerance }

        await check("Route only (volume 100%)", expected: "1.00 (does not double the original)", outputs: [blackHole], chain: EffectChain(), reference: base) { l, r in near(l, 1, 0.05) && near(r, 1, 0.05) }
        await check("Volume 50%", expected: "0.25 (50%² )", outputs: [blackHole], chain: EffectChain(gain: AudioGain.amplitude(volume: 0.5, overdrive: 1, muted: false)), reference: base) { l, _ in near(l, 0.25, 0.03) }
        await check("Mute", expected: "0.00", outputs: [blackHole], chain: EffectChain(gain: 0), reference: base) { l, r in l < 0.01 && r < 0.01 }
        await check("Volume Overdrive 2x", expected: "2.00", outputs: [blackHole], chain: EffectChain(gain: 2), reference: base) { l, _ in near(l, 2, 0.1) }
        await check("EQ 1 kHz +12 dB", expected: "3.98", outputs: [blackHole], chain: EffectChain(equalizers: [EQSettings(gains: [0, 0, 0, 0, 0, 12, 0, 0, 0, 0])]), reference: base) { l, _ in near(l, 3.98, 0.3) }
        await check("EQ 1 kHz −12 dB", expected: "0.25", outputs: [blackHole], chain: EffectChain(equalizers: [EQSettings(gains: [0, 0, 0, 0, 0, -12, 0, 0, 0, 0])]), reference: base) { l, _ in near(l, 0.25, 0.04) }
        await check("Balance full left", expected: "L 1.00, R 0.00", outputs: [blackHole], chain: EffectChain(balance: -1), reference: base) { l, r in near(l, 1, 0.05) && r < 0.01 }
        if let sink {
            await check("Send to another device (\(sink.name))", expected: "0.00 (nothing left on the original device)", outputs: [sink], chain: EffectChain(gain: sinkGain), settle: 0.6, reference: base) { l, r in l < 0.01 && r < 0.01 }
            await check("Output group (BlackHole + \(sink.name))", expected: String(format: "%.2f", sinkGain), outputs: [blackHole, sink], chain: EffectChain(gain: sinkGain), settle: 0.6, reference: base) { l, _ in near(l, sinkGain, 0.08 * sinkGain) }
        }
        let after = await measure()
        rows.append(Row(name: "After every route is down", expected: "1.00 (as before)", left: after.0 / base.0, right: after.1 / base.1, baseline: base.0,
                        pass: near(after.0 / base.0, 1, 0.05)))

        // Magic Boost needs quiet sound: a second tone, ten times softer.
        tone?.terminate()
        tone = startTone(amplitude: 0.02)
        await wait(1.5)
        if let quiet = tone.flatMap({ child in SystemAudio.processes().first { $0.pid == child.processIdentifier } }) {
            let quietBase = await measure()
            do {
                let route = try TapRoute(plan: RoutePlan(structure: RouteStructure(source: .processes([quiet.objectID]), outputUIDs: [blackHole.uid]), chain: EffectChain(magicBoost: true)),
                                         outputs: [blackHole], clock: nil)
                await wait(4)
                let level = await measure()
                route.stop()
                let ratio = level.0 / quietBase.0
                rows.append(Row(name: "Magic Boost (quiet sound 0.02)", expected: "3–4 (target -16 dBFS, at most 4×)", left: ratio, right: level.1 / quietBase.1, baseline: quietBase.0, pass: ratio > 2.8 && ratio <= 4.1))
            } catch {
                rows.append(Row(name: "Magic Boost", expected: "route failed", left: .nan, right: .nan, baseline: quietBase.0, pass: false))
            }
        }

        log("")
        log("| Test | Expected (vs. baseline) | Left | Right | Baseline RMS | Result |")
        log("|---|---|---|---|---|---|")
        for row in rows {
            log("| \(row.name) | \(row.expected) | \(fmt(row.left)) | \(fmt(row.right)) | \(fmt(row.baseline)) | \(row.pass ? "pass" : "fail") |")
        }
        finish("Done: \(rows.filter(\.pass).count)/\(rows.count) passed")
    }

    private func startTone(amplitude: Double) -> Process? {
        guard let executable = Bundle.main.executableURL else { return nil }
        let process = Process()
        process.executableURL = executable
        process.arguments = ["--play-tone", "BlackHole2ch_UID", "1000", "\(amplitude)", "180"]
        return (try? process.run()) == nil ? nil : process
    }

    private func fmt(_ value: Double) -> String { value.isFinite ? String(format: "%.3f", value) : "-" }

    private func finish(_ line: String) {
        log(line)
        log("DONE")
    }
}
#endif
