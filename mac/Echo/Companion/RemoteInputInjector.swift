import AppKit
import CoreGraphics
import Foundation

/// Injects pointer / keyboard events into a target Mac app window.
@MainActor
final class RemoteInputInjector {
    private(set) var targetWindowID: CGWindowID?
    private(set) var targetBundleId: String?
    private var windowBounds: CGRect = .zero

    func setTarget(bundleId: String, windowID: CGWindowID, bounds: CGRect) {
        targetBundleId = bundleId
        targetWindowID = windowID
        windowBounds = bounds
    }

    func clear() {
        targetBundleId = nil
        targetWindowID = nil
        windowBounds = .zero
    }

    func updateBounds(_ bounds: CGRect) {
        windowBounds = bounds
    }

    func handle(_ event: CompanionInputEvent) {
        guard windowBounds.width > 1, windowBounds.height > 1 else { return }
        activateTargetIfNeeded()

        switch event.kind {
        case .tap:
            guard let x = event.x, let y = event.y else { return }
            let point = screenPoint(nx: x, ny: y)
            postMouse(type: .leftMouseDown, at: point)
            postMouse(type: .leftMouseUp, at: point)
        case .down:
            guard let x = event.x, let y = event.y else { return }
            postMouse(type: .leftMouseDown, at: screenPoint(nx: x, ny: y))
        case .up:
            guard let x = event.x, let y = event.y else { return }
            postMouse(type: .leftMouseUp, at: screenPoint(nx: x, ny: y))
        case .move:
            guard let x = event.x, let y = event.y else { return }
            postMouse(type: .mouseMoved, at: screenPoint(nx: x, ny: y))
        case .scroll:
            let dx = event.dx ?? 0
            let dy = event.dy ?? 0
            let point: CGPoint
            if let x = event.x, let y = event.y {
                point = screenPoint(nx: x, ny: y)
            } else {
                point = CGPoint(x: windowBounds.midX, y: windowBounds.midY)
            }
            if let scroll = CGEvent(
                scrollWheelEvent2Source: nil,
                units: .pixel,
                wheelCount: 2,
                wheel1: Int32(-dy * 40),
                wheel2: Int32(dx * 40),
                wheel3: 0
            ) {
                scroll.location = point
                scroll.post(tap: .cghidEventTap)
            }
        case .key:
            guard let key = event.key, !key.isEmpty else { return }
            typeText(key, modifiers: event.modifiers ?? [])
        }
    }

    private func screenPoint(nx: Double, ny: Double) -> CGPoint {
        let x = windowBounds.minX + CGFloat(nx.clamped01) * windowBounds.width
        // Android / UIKit Y grows downward; Quartz screen Y grows upward from bottom-left,
        // but CGEvent uses top-left origin on modern macOS when posting HID events via
        // flipped coordinates — use top-left relative to windowBounds from ScreenCaptureKit
        // (SCK reports top-left origin in display space).
        let y = windowBounds.minY + CGFloat(ny.clamped01) * windowBounds.height
        return CGPoint(x: x, y: y)
    }

    private func postMouse(type: CGEventType, at point: CGPoint) {
        let button: CGMouseButton = .left
        guard let event = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: button)
        else { return }
        event.post(tap: .cghidEventTap)
    }

    private func typeText(_ text: String, modifiers: [String]) {
        let flags = modifierFlags(modifiers)
        for scalar in text.unicodeScalars {
            let keyCode = keyCodeForCharacter(scalar) ?? 0
            if let down = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true) {
                down.flags = flags
                if keyCode == 0 {
                    var chars = UniChar(scalar.value)
                    down.keyboardSetUnicodeString(stringLength: 1, unicodeString: &chars)
                }
                down.post(tap: .cghidEventTap)
            }
            if let up = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: false) {
                up.flags = flags
                up.post(tap: .cghidEventTap)
            }
        }
    }

    private func modifierFlags(_ names: [String]) -> CGEventFlags {
        var flags: CGEventFlags = []
        for name in names {
            switch name.lowercased() {
            case "shift": flags.insert(.maskShift)
            case "command", "cmd", "meta": flags.insert(.maskCommand)
            case "option", "alt": flags.insert(.maskAlternate)
            case "control", "ctrl": flags.insert(.maskControl)
            default: break
            }
        }
        return flags
    }

    private func keyCodeForCharacter(_ scalar: UnicodeScalar) -> CGKeyCode? {
        // Common keys; unicode path handles the rest.
        switch scalar {
        case "\n", "\r": return 36
        case "\t": return 48
        case "\u{8}": return 51 // backspace
        case "\u{1b}": return 53 // escape
        default: return nil
        }
    }

    private func activateTargetIfNeeded() {
        guard let bundleId = targetBundleId else { return }
        let apps = NSWorkspace.shared.runningApplications.filter { $0.bundleIdentifier == bundleId }
        apps.first?.activate(options: [.activateIgnoringOtherApps])
    }
}

private extension Double {
    var clamped01: Double { min(max(self, 0), 1) }
}
