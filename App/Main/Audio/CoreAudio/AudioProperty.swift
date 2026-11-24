import CoreAudio
import Foundation

/// Reading and writing one Core Audio property of one object.
enum AudioProperty {
    static func address(_ selector: AudioObjectPropertySelector, _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
                        _ element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
    }

    static func has(_ object: AudioObjectID, _ address: AudioObjectPropertyAddress) -> Bool {
        var address = address
        return AudioObjectHasProperty(object, &address)
    }

    static func isSettable(_ object: AudioObjectID, _ address: AudioObjectPropertyAddress) -> Bool {
        var address = address
        var settable: DarwinBoolean = false
        return has(object, address) && AudioObjectIsPropertySettable(object, &address, &settable) == noErr && settable.boolValue
    }

    /// A fixed-size value (a number, an object id, a struct).
    static func value<T>(_ object: AudioObjectID, _ address: AudioObjectPropertyAddress, qualifier: UInt32? = nil, initial: T) -> T? {
        var address = address
        var value = initial
        var size = UInt32(MemoryLayout<T>.size)
        var qualifierValue = qualifier ?? 0
        let status = withUnsafeMutableBytes(of: &value) { bytes in
            qualifier == nil
                ? AudioObjectGetPropertyData(object, &address, 0, nil, &size, bytes.baseAddress!)
                : AudioObjectGetPropertyData(object, &address, UInt32(MemoryLayout<UInt32>.size), &qualifierValue, &size, bytes.baseAddress!)
        }
        return status == noErr ? value : nil
    }

    @discardableResult static func set<T>(_ object: AudioObjectID, _ address: AudioObjectPropertyAddress, _ value: T) -> Bool {
        var address = address
        var value = value
        return withUnsafeBytes(of: &value) { bytes in
            AudioObjectSetPropertyData(object, &address, 0, nil, UInt32(bytes.count), bytes.baseAddress!)
        } == noErr
    }

    /// A list of fixed-size values (object ids).
    static func array<T>(_ object: AudioObjectID, _ address: AudioObjectPropertyAddress, of type: T.Type) -> [T] {
        var address = address
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(object, &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        let count = Int(size) / MemoryLayout<T>.stride
        let buffer = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<T>.alignment)
        defer { buffer.deallocate() }
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, buffer) == noErr else { return [] }
        return Array(UnsafeBufferPointer(start: buffer.assumingMemoryBound(to: T.self), count: min(count, Int(size) / MemoryLayout<T>.stride)))
    }

    static func string(_ object: AudioObjectID, _ address: AudioObjectPropertyAddress) -> String? {
        var address = address
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr, let value else { return nil }
        return value.takeRetainedValue() as String
    }

    /// Calls `change` on the main queue whenever one of the system object's `selectors` changes.
    /// Returns what `stopListening` needs.
    static func listen(to selectors: [AudioObjectPropertySelector], on object: AudioObjectID = AudioObjectID(kAudioObjectSystemObject),
                       change: @escaping () -> Void) -> [(AudioObjectPropertyAddress, AudioObjectPropertyListenerBlock)] {
        selectors.compactMap { selector in
            var address = address(selector)
            let block: AudioObjectPropertyListenerBlock = { _, _ in change() }
            return AudioObjectAddPropertyListenerBlock(object, &address, .main, block) == noErr ? (address, block) : nil
        }
    }

    static func stopListening(_ listeners: [(AudioObjectPropertyAddress, AudioObjectPropertyListenerBlock)], on object: AudioObjectID = AudioObjectID(kAudioObjectSystemObject)) {
        for (address, block) in listeners {
            var address = address
            AudioObjectRemovePropertyListenerBlock(object, &address, .main, block)
        }
    }
}
