import AppKit
import Carbon

/// Registers system-wide hotkeys via Carbon's RegisterEventHotKey API.
/// Works without Accessibility permission — no NSEvent global monitor needed.
/// Multiple instances are supported; each gets a unique `id` for dispatch.
@MainActor
final class HotkeyManager {
    var onFire: (() -> Void)?

    private var hotKeyRef: EventHotKeyRef?
    private let hotkeyID: UInt32

    // Shared across all instances — Carbon always fires on the main thread.
    nonisolated(unsafe) private static var _handlers: [UInt32: () -> Void] = [:]
    nonisolated(unsafe) private static var handlerRef: EventHandlerRef?

    init(id: UInt32 = 1) {
        self.hotkeyID = id
    }

    func register(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) {
        if let ref = hotKeyRef { UnregisterEventHotKey(ref); hotKeyRef = nil }
        Self._handlers[hotkeyID] = onFire

        var carbonMods: UInt32 = 0
        if modifiers.contains(.command) { carbonMods |= UInt32(cmdKey)     }
        if modifiers.contains(.option)  { carbonMods |= UInt32(optionKey)  }
        if modifiers.contains(.shift)   { carbonMods |= UInt32(shiftKey)   }
        if modifiers.contains(.control) { carbonMods |= UInt32(controlKey) }

        let hotKeyID = EventHotKeyID(signature: FourCharCode(0x6563_6F68), id: hotkeyID)
        let err = RegisterEventHotKey(
            UInt32(keyCode), carbonMods, hotKeyID,
            GetApplicationEventTarget(), OptionBits(0), &hotKeyRef
        )
        if err != noErr {
            NSLog("HotkeyManager: RegisterEventHotKey failed (err=%d, id=%d).", err, hotkeyID)
            return
        }

        // Install the Carbon event handler once for the lifetime of the app.
        guard Self.handlerRef == nil else { return }
        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind:  OSType(kEventHotKeyPressed)
        )
        InstallEventHandler(
            GetApplicationEventTarget(),
            { (_: EventHandlerCallRef?, event: EventRef?, _: UnsafeMutableRawPointer?) -> OSStatus in
                guard let event else { return noErr }
                var hkID = EventHotKeyID()
                GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hkID
                )
                let id = hkID.id
                Task { @MainActor in HotkeyManager._handlers[id]?() }
                return noErr
            },
            1, &spec, nil, &Self.handlerRef
        )
    }

    func unregister() {
        if let ref = hotKeyRef { UnregisterEventHotKey(ref); hotKeyRef = nil }
        Self._handlers.removeValue(forKey: hotkeyID)
    }
}
