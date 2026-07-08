import AppKit
import Observation

@Observable
@MainActor
final class LauncherSettings {
    // Launcher hotkey
    private static let keyCodeKey   = "launcher_hotkey_keycode"
    private static let modifiersKey = "launcher_hotkey_modifiers"

    var keyCode: UInt16
    var modifiers: NSEvent.ModifierFlags
    var onHotkeyChanged: ((UInt16, NSEvent.ModifierFlags) -> Void)?

    // Clipboard panel hotkey
    private static let clipKeyCodeKey   = "clipboard_hotkey_keycode"
    private static let clipModifiersKey = "clipboard_hotkey_modifiers"

    var clipKeyCode: UInt16
    var clipModifiers: NSEvent.ModifierFlags
    var onClipHotkeyChanged: ((UInt16, NSEvent.ModifierFlags) -> Void)?

    // Browser tabs in launcher search (default off)
    nonisolated static let showTabsInSearchKey = "launcher_show_tabs_in_search"

    var showTabsInSearch: Bool {
        didSet { UserDefaults.standard.set(showTabsInSearch, forKey: Self.showTabsInSearchKey) }
    }

    init() {
        let stored     = UserDefaults.standard.integer(forKey: Self.keyCodeKey)
        let storedMods = UserDefaults.standard.integer(forKey: Self.modifiersKey)
        keyCode   = stored != 0 ? UInt16(stored) : 1
        modifiers = storedMods != 0
            ? NSEvent.ModifierFlags(rawValue: UInt(storedMods))
            : .option

        let storedClip     = UserDefaults.standard.integer(forKey: Self.clipKeyCodeKey)
        let storedClipMods = UserDefaults.standard.integer(forKey: Self.clipModifiersKey)
        clipKeyCode   = storedClip != 0 ? UInt16(storedClip) : 9          // default: V
        clipModifiers = storedClipMods != 0
            ? NSEvent.ModifierFlags(rawValue: UInt(storedClipMods))
            : [.command, .shift]                                           // default: ⌘⇧

        showTabsInSearch = UserDefaults.standard.bool(forKey: Self.showTabsInSearchKey)
    }

    nonisolated static var storedShowTabsInSearch: Bool {
        UserDefaults.standard.bool(forKey: showTabsInSearchKey)
    }

    func save(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) {
        self.keyCode   = keyCode
        self.modifiers = modifiers
        UserDefaults.standard.set(Int(keyCode),            forKey: Self.keyCodeKey)
        UserDefaults.standard.set(Int(modifiers.rawValue), forKey: Self.modifiersKey)
        onHotkeyChanged?(keyCode, modifiers)
    }

    func saveClip(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) {
        self.clipKeyCode   = keyCode
        self.clipModifiers = modifiers
        UserDefaults.standard.set(Int(keyCode),            forKey: Self.clipKeyCodeKey)
        UserDefaults.standard.set(Int(modifiers.rawValue), forKey: Self.clipModifiersKey)
        onClipHotkeyChanged?(keyCode, modifiers)
    }

    var displayString: String { hotkeyString(keyCode: keyCode, modifiers: modifiers) }
    var clipDisplayString: String { hotkeyString(keyCode: clipKeyCode, modifiers: clipModifiers) }

    private func hotkeyString(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) -> String {
        var parts: [String] = []
        if modifiers.contains(.control) { parts.append("⌃") }
        if modifiers.contains(.option)  { parts.append("⌥") }
        if modifiers.contains(.shift)   { parts.append("⇧") }
        if modifiers.contains(.command) { parts.append("⌘") }
        parts.append(Self.keyName(for: keyCode))
        return parts.joined()
    }

    static func keyName(for keyCode: UInt16) -> String {
        let map: [UInt16: String] = [
            0:  "A", 1:  "S", 2:  "D", 3:  "F", 4:  "H", 5:  "G", 6:  "Z", 7:  "X",
            8:  "C", 9:  "V", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y",
            17: "T", 31: "O", 32: "U", 34: "I", 35: "P", 37: "L", 38: "J", 40: "K",
            45: "N", 46: "M",
            18: "1", 19: "2", 20: "3", 21: "4", 22: "6", 23: "5",
            25: "9", 26: "7", 28: "8", 29: "0",
            36: "↩", 48: "⇥", 49: "Space", 51: "⌫", 53: "⎋",
            123: "←", 124: "→", 125: "↓", 126: "↑",
        ]
        return map[keyCode] ?? "key(\(keyCode))"
    }
}
