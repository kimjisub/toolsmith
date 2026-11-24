import AppKit
import AudioToolbox
import CoreAudio
import ToolsmithKit

/// An audio device the system offers.
struct AudioDevice: Identifiable, Hashable {
    let id: AudioObjectID
    let uid: String
    let name: String
    let hasOutput: Bool
    let hasInput: Bool
    let transport: UInt32
}

/// The three system-wide device choices.
enum DeviceRole: CaseIterable {
    case output, input, effects

    var selector: AudioObjectPropertySelector {
        switch self {
        case .output: return kAudioHardwarePropertyDefaultOutputDevice
        case .input: return kAudioHardwarePropertyDefaultInputDevice
        case .effects: return kAudioHardwarePropertyDefaultSystemOutputDevice
        }
    }

    var scope: AudioObjectPropertyScope { self == .input ? kAudioObjectPropertyScopeInput : kAudioObjectPropertyScopeOutput }
}

/// The Mac's devices, its default choices, device volumes and the processes playing sound,
/// through Core Audio's public properties.
enum SystemAudio {
    /// UIDs of the aggregate devices the mixer makes for itself; they are never offered as devices.
    static let routeUIDPrefix = "\(AppIdentity.bundleID).route."
    private static let system = AudioObjectID(kAudioObjectSystemObject)

    static func devices() -> [AudioDevice] {
        AudioProperty.array(system, AudioProperty.address(kAudioHardwarePropertyDevices), of: AudioObjectID.self).compactMap { id in
            guard let uid = AudioProperty.string(id, AudioProperty.address(kAudioDevicePropertyDeviceUID)), !uid.hasPrefix(routeUIDPrefix) else { return nil }
            let hidden = AudioProperty.value(id, AudioProperty.address(kAudioDevicePropertyIsHidden), initial: UInt32(0)) ?? 0
            guard hidden == 0 else { return nil }
            let name = AudioProperty.string(id, AudioProperty.address(kAudioObjectPropertyName)) ?? uid
            return AudioDevice(id: id, uid: uid, name: name,
                               hasOutput: hasStreams(id, kAudioObjectPropertyScopeOutput), hasInput: hasStreams(id, kAudioObjectPropertyScopeInput),
                               transport: AudioProperty.value(id, AudioProperty.address(kAudioDevicePropertyTransportType), initial: UInt32(0)) ?? 0)
        }
    }

    private static func hasStreams(_ device: AudioObjectID, _ scope: AudioObjectPropertyScope) -> Bool {
        !AudioProperty.array(device, AudioProperty.address(kAudioDevicePropertyStreams, scope), of: AudioObjectID.self).isEmpty
    }

    static func defaultDevice(_ role: DeviceRole) -> AudioObjectID? {
        let id = AudioProperty.value(system, AudioProperty.address(role.selector), initial: AudioObjectID(kAudioObjectUnknown))
        return id == AudioObjectID(kAudioObjectUnknown) ? nil : id
    }

    @discardableResult static func setDefault(_ role: DeviceRole, to device: AudioObjectID) -> Bool {
        AudioProperty.set(system, AudioProperty.address(role.selector), device)
    }

    // MARK: Volume and mute

    /// Most devices have one volume for all channels; some only a volume on their main element.
    private static func volumeAddress(_ device: AudioObjectID, _ scope: AudioObjectPropertyScope) -> AudioObjectPropertyAddress? {
        let virtualMain = AudioProperty.address(kAudioHardwareServiceDeviceProperty_VirtualMainVolume, scope)
        if AudioProperty.has(device, virtualMain) { return virtualMain }
        let scalar = AudioProperty.address(kAudioDevicePropertyVolumeScalar, scope)
        return AudioProperty.has(device, scalar) ? scalar : nil
    }

    static func volume(_ device: AudioObjectID, _ role: DeviceRole) -> Double? {
        guard let address = volumeAddress(device, role.scope) else { return nil }
        return AudioProperty.value(device, address, initial: Float32(0)).map(Double.init)
    }

    static func canSetVolume(_ device: AudioObjectID, _ role: DeviceRole) -> Bool {
        volumeAddress(device, role.scope).map { AudioProperty.isSettable(device, $0) } ?? false
    }

    static func setVolume(_ device: AudioObjectID, _ role: DeviceRole, _ volume: Double) {
        guard let address = volumeAddress(device, role.scope) else { return }
        AudioProperty.set(device, address, Float32(min(max(volume, 0), 1)))
    }

    static func isMuted(_ device: AudioObjectID, _ role: DeviceRole) -> Bool? {
        AudioProperty.value(device, AudioProperty.address(kAudioDevicePropertyMute, role.scope), initial: UInt32(0)).map { $0 != 0 }
    }

    static func canMute(_ device: AudioObjectID, _ role: DeviceRole) -> Bool {
        AudioProperty.isSettable(device, AudioProperty.address(kAudioDevicePropertyMute, role.scope))
    }

    static func setMuted(_ device: AudioObjectID, _ role: DeviceRole, _ muted: Bool) {
        AudioProperty.set(device, AudioProperty.address(kAudioDevicePropertyMute, role.scope), UInt32(muted ? 1 : 0))
    }

    // MARK: Balance and sample rate

    private static func balanceAddress(_ role: DeviceRole) -> AudioObjectPropertyAddress {
        AudioProperty.address(kAudioHardwareServiceDeviceProperty_VirtualMainBalance, role.scope)
    }

    /// −1 (left) … 0 (centred) … 1 (right); nil for a device without per-channel volume.
    static func balance(_ device: AudioObjectID, _ role: DeviceRole) -> Double? {
        AudioProperty.value(device, balanceAddress(role), initial: Float32(0.5)).map { Double($0) * 2 - 1 }
    }

    static func canSetBalance(_ device: AudioObjectID, _ role: DeviceRole) -> Bool {
        AudioProperty.isSettable(device, balanceAddress(role))
    }

    static func setBalance(_ device: AudioObjectID, _ role: DeviceRole, _ balance: Double) {
        AudioProperty.set(device, balanceAddress(role), Float32((min(max(balance, -1), 1) + 1) / 2))
    }

    static func sampleRate(_ device: AudioObjectID) -> Double? {
        AudioProperty.value(device, AudioProperty.address(kAudioDevicePropertyNominalSampleRate), initial: Float64(0))
    }

    /// The usual rates the device accepts.
    static func sampleRates(_ device: AudioObjectID) -> [Double] {
        let ranges = AudioProperty.array(device, AudioProperty.address(kAudioDevicePropertyAvailableNominalSampleRates), of: AudioValueRange.self)
        return [22_050, 32_000, 44_100, 48_000, 88_200, 96_000, 176_400, 192_000].filter { rate in
            ranges.contains { $0.mMinimum <= rate && rate <= $0.mMaximum }
        }
    }

    static func setSampleRate(_ device: AudioObjectID, _ rate: Double) {
        AudioProperty.set(device, AudioProperty.address(kAudioDevicePropertyNominalSampleRate), Float64(rate))
    }

    // MARK: Alert volume

    /// Core Audio has no property for it; the scripting addition's alert volume is the public way.
    @MainActor static func alertVolume() -> Double? {
        var error: NSDictionary?
        guard let result = NSAppleScript(source: "alert volume of (get volume settings)")?.executeAndReturnError(&error), error == nil else { return nil }
        return Double(result.int32Value) / 100
    }

    @MainActor static func setAlertVolume(_ volume: Double) {
        var error: NSDictionary?
        NSAppleScript(source: "set volume alert volume \(Int((min(max(volume, 0), 1) * 100).rounded()))")?.executeAndReturnError(&error)
    }

    // MARK: Processes

    static func processes() -> [AudioProcessEntry] {
        AudioProperty.array(system, AudioProperty.address(kAudioHardwarePropertyProcessObjectList), of: AudioObjectID.self).compactMap { id in
            guard let pid = AudioProperty.value(id, AudioProperty.address(kAudioProcessPropertyPID), initial: pid_t(0)) else { return nil }
            let playing = AudioProperty.value(id, AudioProperty.address(kAudioProcessPropertyIsRunningOutput), initial: UInt32(0)) ?? 0
            return AudioProcessEntry(objectID: id, pid: pid, bundleID: AudioProperty.string(id, AudioProperty.address(kAudioProcessPropertyBundleID)),
                                     executablePath: ProcessPath.executable(of: pid), isPlaying: playing != 0)
        }
    }

    /// This app's own process object, once it is a client of the audio system.
    static func ownProcessObject() -> AudioObjectID? {
        let id = AudioProperty.value(system, AudioProperty.address(kAudioHardwarePropertyTranslatePIDToProcessObject),
                                     qualifier: UInt32(bitPattern: getpid()), initial: AudioObjectID(kAudioObjectUnknown))
        return id == AudioObjectID(kAudioObjectUnknown) ? nil : id
    }
}
