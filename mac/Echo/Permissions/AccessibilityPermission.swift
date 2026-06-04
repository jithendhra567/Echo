import AppKit
import ApplicationServices

enum AccessibilityPermission {
    static var isGranted: Bool {
        AXIsProcessTrusted()
    }

    /// Opens the system Accessibility prompt when not yet trusted.
    static func requestIfNeeded() {
        guard !isGranted else { return }
        let options = ["AXTrustedCheckOptionPrompt" as CFString: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    static func openSystemSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}
