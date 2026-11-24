import AudioToolbox
import CoreAudio
import Foundation
import ToolsmithKit

enum TapRouteError: Error {
    case tap(OSStatus)
    case device(OSStatus)
    case format
    case start(OSStatus)
    case noOutput

    var message: String {
        switch self {
        case .tap(let status): return String(localized: "Couldn’t receive the app’s audio (\(status))")
        case .device(let status): return String(localized: "Couldn’t create the audio route (\(status))")
        case .format: return String(localized: "This output device’s audio format isn’t supported")
        case .start(let status): return String(localized: "Couldn’t start the audio route (\(status))")
        case .noOutput: return String(localized: "Couldn’t find the output device")
        }
    }
}

/// One route: a process tap and a private aggregate device made of the tap and the output devices.
/// A route with outputs takes the apps' sound away from the hardware (only while it is being read,
/// so their sound comes back if this app quits) and its IOProc plays it on the outputs through the
/// processor. A meter has no outputs: its tap leaves the sound alone and the IOProc only measures.
final class TapRoute {
    let structure: RouteStructure
    let processor: AudioProcessor
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var deviceID = AudioObjectID(kAudioObjectUnknown)
    private var procID: AudioDeviceIOProcID?
    /// The tap's stream on its own: the aggregate's input also holds the output devices' own inputs
    /// (BlackHole's loopback, for one), which must not be played back out.
    private let tapInput: UnsafeMutableAudioBufferListPointer

    /// `outputs` are the devices of `plan.structure.outputUIDs`, in that order. A meter, which has
    /// none, still needs a device to keep time: `clock`, whose output it leaves silent.
    init(plan: RoutePlan, outputs: [AudioDevice], clock: AudioDevice?) throws {
        structure = plan.structure
        guard let timekeeper = outputs.first ?? clock else { throw TapRouteError.noOutput }
        let (tap, device) = try Self.makeTapAndDevice(plan.structure.source, devices: outputs.isEmpty ? [timekeeper] : outputs, mutes: !outputs.isEmpty)
        tapID = tap
        deviceID = device
        let sampleRate = AudioProperty.value(device, AudioProperty.address(kAudioDevicePropertyNominalSampleRate), initial: Float64(48_000)) ?? 48_000
        let processor = AudioProcessor(sampleRate: sampleRate, chain: plan.chain)
        self.processor = processor
        // The devices' input streams come first in the aggregate, the tap's after them.
        let tapIndex = (outputs.isEmpty ? [timekeeper] : outputs).reduce(0) { count, device in
            count + AudioProperty.array(device.id, AudioProperty.address(kAudioDevicePropertyStreams, kAudioObjectPropertyScopeInput), of: AudioObjectID.self).count
        }
        let tapInput = AudioBufferList.allocate(maximumBuffers: 1)
        self.tapInput = tapInput

        var proc: AudioDeviceIOProcID?
        let procStatus: OSStatus
        if outputs.isEmpty {
            procStatus = AudioDeviceCreateIOProcIDWithBlock(&proc, device, nil) { _, input, _, output, _ in
                if AudioBufferCopy.pick(tapIndex, from: input, into: tapInput.unsafeMutablePointer) { processor.measure(tapInput.unsafePointer) }
                for buffer in UnsafeMutableAudioBufferListPointer(output) {
                    if let data = buffer.mData { memset(data, 0, Int(buffer.mDataByteSize)) }
                }
            }
        } else {
            let replicate = outputs.count > 1
            procStatus = AudioDeviceCreateIOProcIDWithBlock(&proc, device, nil) { _, input, _, output, _ in
                guard AudioBufferCopy.pick(tapIndex, from: input, into: tapInput.unsafeMutablePointer) else { return }
                AudioBufferCopy.copy(from: tapInput.unsafePointer, to: output, replicate: replicate)
                processor.process(output)
            }
        }
        procID = proc
        guard procStatus == noErr, let proc else {
            stop()
            throw TapRouteError.start(procStatus)
        }
        let startStatus = AudioDeviceStart(device, proc)
        guard startStatus == noErr else {
            stop()
            throw TapRouteError.start(startStatus)
        }
    }

    deinit {
        stop()
        free(tapInput.unsafeMutablePointer)
    }

    func update(_ plan: RoutePlan) {
        processor.set(plan.chain)
    }

    /// Takes the route apart; the apps' sound goes back to the hardware.
    func stop() {
        if let procID, deviceID != AudioObjectID(kAudioObjectUnknown) {
            AudioDeviceStop(deviceID, procID)
            AudioDeviceDestroyIOProcID(deviceID, procID)
        }
        procID = nil
        if deviceID != AudioObjectID(kAudioObjectUnknown) { AudioHardwareDestroyAggregateDevice(deviceID) }
        deviceID = AudioObjectID(kAudioObjectUnknown)
        if tapID != AudioObjectID(kAudioObjectUnknown) { AudioHardwareDestroyProcessTap(tapID) }
        tapID = AudioObjectID(kAudioObjectUnknown)
    }

    /// The tap and the aggregate device around it; on failure whatever was made is destroyed again.
    /// The first output keeps time; the others, and the tap, are resampled against it when needed.
    private static func makeTapAndDevice(_ source: TapSource, devices outputs: [AudioDevice], mutes: Bool) throws -> (AudioObjectID, AudioObjectID) {
        let description: CATapDescription
        switch source {
        case .processes(let ids): description = CATapDescription(stereoMixdownOfProcesses: ids)
        case .everythingExcept(let ids): description = CATapDescription(stereoGlobalTapButExcludeProcesses: ids)
        }
        description.name = AppIdentity.name
        description.uuid = UUID()
        description.muteBehavior = mutes ? .mutedWhenTapped : .unmuted
        description.isPrivate = true

        var tap = AudioObjectID(kAudioObjectUnknown)
        let tapStatus = AudioHardwareCreateProcessTap(description, &tap)
        guard tapStatus == noErr else { throw TapRouteError.tap(tapStatus) }

        let clock = outputs.first
        var composition: [String: Any] = [
            kAudioAggregateDeviceNameKey: "\(AppIdentity.name) Audio Route",
            kAudioAggregateDeviceUIDKey: SystemAudio.routeUIDPrefix + UUID().uuidString,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceTapListKey: [[
                kAudioSubTapUIDKey: description.uuid.uuidString,
                kAudioSubTapDriftCompensationKey: clock.map { AudioRoutes.compensatesDrift(outputTransport: $0.transport) } ?? false,
            ]],
        ]
        if let clock {
            composition[kAudioAggregateDeviceMainSubDeviceKey] = clock.uid
            composition[kAudioAggregateDeviceSubDeviceListKey] = outputs.enumerated().map { index, device in
                [kAudioSubDeviceUIDKey: device.uid, kAudioSubDeviceDriftCompensationKey: index > 0] as [String: Any]
            }
        }
        var device = AudioObjectID(kAudioObjectUnknown)
        let deviceStatus = AudioHardwareCreateAggregateDevice(composition as CFDictionary, &device)
        guard deviceStatus == noErr else {
            AudioHardwareDestroyProcessTap(tap)
            throw TapRouteError.device(deviceStatus)
        }
        // The copy and the processor work on 32-bit float on both sides, which is what the HAL hands IOProcs.
        guard isFloat(device, kAudioObjectPropertyScopeInput), isFloat(device, kAudioObjectPropertyScopeOutput) else {
            AudioHardwareDestroyAggregateDevice(device)
            AudioHardwareDestroyProcessTap(tap)
            throw TapRouteError.format
        }
        return (tap, device)
    }

    #if TOOLSMITH_DEV
    /// Development aid: makes a tap of no process and its device on `output`, then takes them apart
    /// without starting anything (starting is what asks for the permission).
    static func probe(output: AudioDevice) -> String {
        do {
            let (tap, device) = try makeTapAndDevice(.processes([]), devices: [output], mutes: true)
            let rate = AudioProperty.value(device, AudioProperty.address(kAudioDevicePropertyNominalSampleRate), initial: Float64(0)) ?? 0
            AudioHardwareDestroyAggregateDevice(device)
            AudioHardwareDestroyProcessTap(tap)
            return "ok, tap \(tap) device \(device) at \(Int(rate)) Hz"
        } catch {
            return "failed: \((error as? TapRouteError)?.message ?? error.localizedDescription)"
        }
    }
    #endif

    private static func isFloat(_ device: AudioObjectID, _ scope: AudioObjectPropertyScope) -> Bool {
        let streams = AudioProperty.array(device, AudioProperty.address(kAudioDevicePropertyStreams, scope), of: AudioObjectID.self)
        return streams.allSatisfy { stream in
            guard let format = AudioProperty.value(stream, AudioProperty.address(kAudioStreamPropertyVirtualFormat), initial: AudioStreamBasicDescription()) else { return false }
            return format.mFormatID == kAudioFormatLinearPCM && format.mFormatFlags & kAudioFormatFlagIsFloat != 0 && format.mBitsPerChannel == 32
        }
    }
}

/// Builds, changes and takes apart routes on a queue of its own: making a tap and an aggregate
/// device takes a moment, and on the main thread that moment froze the slider being dragged.
/// Work is done in the order it is asked for; results come back on the main thread.
final class RouteEngine: @unchecked Sendable {
    private let queue = DispatchQueue(label: "\(AppIdentity.bundleID).audio-routes", qos: .userInitiated)
    /// Only touched on `queue`.
    private var routes: [String: TapRoute] = [:]
    /// The processors by route, for the meters, readable from the main thread.
    private let processorLock = NSLock()
    private var processors: [String: AudioProcessor] = [:]

    /// `finished` gets the error of each route that could not start (nil for those that did).
    /// Meters keep time by `clock` (the system output).
    func apply(_ changes: RouteChanges, plans: [String: RoutePlan], devices: [AudioDevice], clock: AudioDevice?,
               finished: @escaping @MainActor ([String: String?]) -> Void) {
        guard !(changes.stop.isEmpty && changes.start.isEmpty && changes.update.isEmpty) else { return }
        queue.async { [self] in
            for key in changes.stop { take(key)?.stop() }
            for key in changes.update { if let plan = plans[key] { routes[key]?.update(plan) } }
            var results: [String: String?] = [:]
            for key in changes.start {
                guard let plan = plans[key] else { continue }
                do {
                    let outputs = try plan.structure.outputUIDs.map { uid in
                        guard let device = devices.first(where: { $0.uid == uid }) else { throw TapRouteError.noOutput }
                        return device
                    }
                    let route = try TapRoute(plan: plan, outputs: outputs, clock: clock)
                    routes[key] = route
                    processorLock.withLock { processors[key] = route.processor }
                    results[key] = .some(nil)
                } catch {
                    results[key] = .some((error as? TapRouteError)?.message ?? error.localizedDescription)
                }
            }
            if !results.isEmpty { DispatchQueue.main.async { MainActor.assumeIsolated { finished(results) } } }
        }
    }

    /// The latest levels of the routes and meters running, by key: (before the effects, after them).
    func levels() -> [String: (input: Float, output: Float)] {
        processorLock.withLock { processors.mapValues { ($0.inputPeak, $0.outputPeak) } }
    }

    /// Everything down before returning: at quit the apps get their sound back.
    func stopAll() {
        queue.sync { for key in Array(routes.keys) { take(key)?.stop() } }
    }

    private func take(_ key: String) -> TapRoute? {
        processorLock.withLock { _ = processors.removeValue(forKey: key) }
        return routes.removeValue(forKey: key)
    }
}
