import CoreAudio
import Foundation

/// Where a route takes its sound from.
public enum TapSource: Hashable, Sendable {
    /// The given process objects, mixed down to stereo.
    case processes([UInt32])
    /// Everything except the given process objects.
    case everythingExcept([UInt32])
}

/// The parts of a route that need a new tap and device to change.
public struct RouteStructure: Hashable, Sendable {
    public let source: TapSource
    /// The devices the sound is played on, the first keeping time. Empty for a meter, which only
    /// listens: its tap leaves the sound where it was.
    public let outputUIDs: [String]

    public init(source: TapSource, outputUIDs: [String]) {
        self.source = source
        self.outputUIDs = outputUIDs
    }

    public var isMeter: Bool { outputUIDs.isEmpty }
}

/// One route the mixer should have running.
public struct RoutePlan: Equatable, Sendable {
    public let structure: RouteStructure
    public let chain: EffectChain

    public init(structure: RouteStructure, chain: EffectChain) {
        self.structure = structure
        self.chain = chain
    }
}

public struct RouteChanges: Equatable, Sendable {
    /// Routes to take down (gone, or rebuilt because their structure changed).
    public var stop: [String] = []
    /// Routes to build (new, or rebuilt).
    public var start: [String] = []
    /// Routes that stay and only take new values.
    public var update: [String] = []

    public init(stop: [String] = [], start: [String] = [], update: [String] = []) {
        self.stop = stop
        self.start = start
        self.update = update
    }
}

public enum AudioRoutes {
    /// The key of the route that applies the system output's effects to everything not routed on its
    /// own. Bundle ids never start with "*".
    public static let systemKey = "*system"
    /// Meter routes are keyed by what they measure after this.
    public static let meterPrefix = "meter:"
    /// What the output's meter is keyed by.
    public static let outputMeterKey = meterPrefix + "*output"

    /// The devices an app's sound goes to: its own choice (a device or a group) as far as connected,
    /// else the system output.
    public static func outputs(for setting: String?, groups: [OutputGroup], defaultOutputUID: String?, connected: Set<String>) -> [String] {
        if let setting {
            let chosen: [String]
            if setting.hasPrefix(OutputGroup.prefix) {
                chosen = groups.first { $0.reference == setting }?.deviceUIDs ?? []
            } else {
                chosen = [setting]
            }
            let present = chosen.filter(connected.contains)
            if !present.isEmpty { return present }
        }
        return defaultOutputUID.map { [$0] } ?? []
    }

    /// The routes the current settings call for. `ownProcessID` is this app's process object: the
    /// system effects route leaves it out (its own output would come back in), and without it there
    /// is no such route. `muted` are the apps under a timed mute.
    public static func plan(groups: [AudioAppGroup], settings: [String: AppAudioSettings], system: SystemEffects, outputGroups: [OutputGroup],
                            defaultOutputUID: String?, connected: Set<String>, ownProcessID: UInt32?, muted: Set<String> = []) -> [String: RoutePlan] {
        let systemChain = system.chain
        let systemActive = !systemChain.isNeutral && ownProcessID != nil && defaultOutputUID != nil
        var plans: [String: RoutePlan] = [:]
        var routed: [UInt32] = []
        for group in groups where !group.processIDs.isEmpty {
            let app = settings[group.key] ?? AppAudioSettings()
            let forcedMute = muted.contains(group.key)
            guard !app.isNeutral || forcedMute else { continue }
            let outputs = outputs(for: app.outputUID, groups: outputGroups, defaultOutputUID: defaultOutputUID, connected: connected)
            guard !outputs.isEmpty else { continue }
            // An app sent to the system output skips the system route, so it takes the system's effects itself.
            var chain = app.chain(muted: forcedMute)
            if systemActive, outputs == [defaultOutputUID] { chain = chain.then(systemChain) }
            plans[group.key] = RoutePlan(structure: RouteStructure(source: .processes(group.processIDs), outputUIDs: outputs), chain: chain)
            routed += group.processIDs
        }
        if systemActive, let ownProcessID, let defaultOutputUID {
            let excluded = Array(Set(routed + [ownProcessID])).sorted()
            plans[systemKey] = RoutePlan(structure: RouteStructure(source: .everythingExcept(excluded), outputUIDs: [defaultOutputUID]), chain: systemChain)
        }
        return plans
    }

    /// Meters for what the mixer shows while open: the system output (everything), and every
    /// playing app that has no route of its own (a route measures its app itself).
    public static func meterPlans(groups: [AudioAppGroup], routed: Set<String>) -> [String: RoutePlan] {
        var plans = [outputMeterKey: RoutePlan(structure: RouteStructure(source: .everythingExcept([]), outputUIDs: []), chain: EffectChain())]
        for group in groups where group.isPlaying && !routed.contains(group.key) && !group.processIDs.isEmpty {
            plans[meterPrefix + group.key] = RoutePlan(structure: RouteStructure(source: .processes(group.processIDs), outputUIDs: []), chain: EffectChain())
        }
        return plans
    }

    /// Whether the tap is resampled against the output's clock. Bluetooth and virtual outputs keep
    /// time their own way, and resampling against them crackles every so often.
    public static func compensatesDrift(outputTransport: UInt32) -> Bool {
        ![kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE, kAudioDeviceTransportTypeVirtual].contains(outputTransport)
    }

    public static func changes(running: [String: RouteStructure], desired: [String: RoutePlan]) -> RouteChanges {
        var changes = RouteChanges()
        for (key, structure) in running.sorted(by: { $0.key < $1.key }) {
            guard let plan = desired[key] else {
                changes.stop.append(key)
                continue
            }
            if plan.structure == structure {
                changes.update.append(key)
            } else {
                changes.stop.append(key)
                changes.start.append(key)
            }
        }
        changes.start += desired.keys.filter { running[$0] == nil }.sorted()
        return changes
    }
}
