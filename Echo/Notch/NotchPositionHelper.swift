import AppKit

enum NotchPositionHelper {
    /// Height of the menu bar (including notch overhang) on the given screen.
    static func menuBarHeight(for screen: NSScreen) -> CGFloat {
        screen.frame.maxY - screen.visibleFrame.maxY
    }

    /// True when the screen has a hardware notch (safeAreaInsets.top > 0).
    static func hasNotch(_ screen: NSScreen) -> Bool {
        screen.safeAreaInsets.top > 0
    }

    /// Horizontal center for the tray — always the screen midpoint (notch center).
    static func trayCenterX(for screen: NSScreen) -> CGFloat {
        screen.frame.midX
    }

    /// The Y coordinate of the bottom of the menu bar (top of the visible workspace).
    static func menuBarBaseY(for screen: NSScreen) -> CGFloat {
        screen.visibleFrame.maxY
    }
}
