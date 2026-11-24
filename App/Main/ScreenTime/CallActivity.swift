import CoreAudio
import CoreMediaIO
import Foundation

/// Whether a video or voice call is likely under way: another app is reading a microphone, or a
/// camera is on. These are the states macOS shows as the orange and green dots in the menu bar.
/// Reading them needs neither the microphone nor the camera permission.
enum CallActivity {
    static var isActive: Bool { anotherAppReadsAMicrophone || aCameraIsOn }

    /// Core Audio lists the processes using audio. The app itself (recording the screen with
    /// the microphone) does not count.
    private static var anotherAppReadsAMicrophone: Bool {
        let own = ProcessInfo.processInfo.processIdentifier
        return audioObjects(of: AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyProcessObjectList).contains { process in
            audioValue(of: process, kAudioProcessPropertyIsRunningInput, as: UInt32.self) == 1
                && audioValue(of: process, kAudioProcessPropertyPID, as: pid_t.self) != own
        }
    }

    private static var aCameraIsOn: Bool {
        cameraObjects(of: CMIOObjectID(kCMIOObjectSystemObject), kCMIOHardwarePropertyDevices).contains { device in
            cameraValue(of: device, kCMIODevicePropertyDeviceIsRunningSomewhere, as: UInt32.self) == 1
        }
    }

    // MARK: Core Audio

    private static func audioAddress(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    }

    private static func audioObjects(of object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> [AudioObjectID] {
        var address = audioAddress(selector)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(object, &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &ids) == noErr else { return [] }
        return Array(ids.prefix(Int(size) / MemoryLayout<AudioObjectID>.size))
    }

    private static func audioValue<T: FixedWidthInteger>(of object: AudioObjectID, _ selector: AudioObjectPropertySelector, as: T.Type) -> T? {
        var address = audioAddress(selector)
        var value: T = 0
        var size = UInt32(MemoryLayout<T>.size)
        return AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr ? value : nil
    }

    // MARK: Core Media IO (cameras)

    private static func cameraAddress(_ selector: Int) -> CMIOObjectPropertyAddress {
        CMIOObjectPropertyAddress(mSelector: CMIOObjectPropertySelector(selector),
                                  mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
                                  mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
    }

    private static func cameraObjects(of object: CMIOObjectID, _ selector: Int) -> [CMIOObjectID] {
        var address = cameraAddress(selector)
        var size: UInt32 = 0
        guard CMIOObjectGetPropertyDataSize(object, &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [CMIOObjectID](repeating: 0, count: Int(size) / MemoryLayout<CMIOObjectID>.size)
        var used: UInt32 = 0
        guard CMIOObjectGetPropertyData(object, &address, 0, nil, size, &used, &ids) == noErr else { return [] }
        return Array(ids.prefix(Int(used) / MemoryLayout<CMIOObjectID>.size))
    }

    private static func cameraValue<T: FixedWidthInteger>(of object: CMIOObjectID, _ selector: Int, as: T.Type) -> T? {
        var address = cameraAddress(selector)
        var value: T = 0
        var used: UInt32 = 0
        return CMIOObjectGetPropertyData(object, &address, 0, nil, UInt32(MemoryLayout<T>.size), &used, &value) == noErr ? value : nil
    }
}
