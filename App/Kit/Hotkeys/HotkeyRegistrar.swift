import Carbon.HIToolbox
import Foundation

/// Registers global shortcuts with the system (Carbon hot keys: the only API that both
/// receives the key from any app and keeps it from reaching that app).
public final class HotkeyRegistrar {
    /// Called on the main thread with the id of the action whose shortcut was pressed.
    public var onFire: ((String) -> Void)?

    private static let signature: OSType = 0x435A_5554 // 'CZUT'
    private var handler: EventHandlerRef?
    private var registered: [EventHotKeyRef] = []
    private var actionByNumber: [UInt32: String] = [:]

    public init() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetEventDispatcherTarget(), { _, event, userData in
            guard let event, let userData else { return OSStatus(eventNotHandledErr) }
            var hotKey = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                           nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKey)
            guard status == noErr else { return status }
            Unmanaged<HotkeyRegistrar>.fromOpaque(userData).takeUnretainedValue().fire(hotKey.id)
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &handler)
    }

    deinit {
        unregisterAll()
        if let handler { RemoveEventHandler(handler) }
    }

    /// Replaces every registration with `table`. Returns the bindings the system refused,
    /// which usually means another app already holds that key.
    @discardableResult public func apply(_ table: HotkeyTable) -> [String: KeyCombo] {
        unregisterAll()
        var failed: [String: KeyCombo] = [:]
        var number: UInt32 = 1
        for (id, combo) in table.bindings.sorted(by: { $0.key < $1.key }) {
            var ref: EventHotKeyRef?
            let status = RegisterEventHotKey(UInt32(combo.keyCode), Self.carbonModifiers(combo.modifiers),
                                             EventHotKeyID(signature: Self.signature, id: number),
                                             GetEventDispatcherTarget(), 0, &ref)
            if status == noErr, let ref {
                registered.append(ref)
                actionByNumber[number] = id
            } else {
                failed[id] = combo
            }
            number += 1
        }
        return failed
    }

    public func unregisterAll() {
        registered.forEach { UnregisterEventHotKey($0) }
        registered = []
        actionByNumber = [:]
    }

    private func fire(_ number: UInt32) {
        guard let id = actionByNumber[number] else { return }
        onFire?(id)
    }

    static func carbonModifiers(_ modifiers: KeyModifiers) -> UInt32 {
        var flags = 0
        if modifiers.contains(.control) { flags |= controlKey }
        if modifiers.contains(.option) { flags |= optionKey }
        if modifiers.contains(.shift) { flags |= shiftKey }
        if modifiers.contains(.command) { flags |= cmdKey }
        return UInt32(flags)
    }
}
