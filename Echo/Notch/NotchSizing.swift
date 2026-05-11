import AppKit
import CoreGraphics

/// Central sizing constants — single source of truth for the entire notch
/// subsystem. Mirrors `sizing/matters.swift` in TheBoredTeam/boring.notch.
enum NotchSizing {
    /// Padding around the window to make room for shadow / overshoot.
    static let shadowPadding: CGFloat = 20

    /// The exact frame the pill occupies when expanded.
    static let openSize = CGSize(width: 520, height: 160)

    /// Total NSWindow size — wide enough to contain the maximum open pill plus
    /// shadow room. The window itself never resizes, only its SwiftUI content.
    static let windowSize = CGSize(
        width:  openSize.width  + shadowPadding * 2,
        height: openSize.height + shadowPadding
    )

    /// Corner radii at both notch states. Both interpolate via NotchShape.
    enum Corners {
        static let closedTop:    CGFloat = 6
        static let closedBottom: CGFloat = 14
        static let openTop:      CGFloat = 19
        static let openBottom:   CGFloat = 24
    }

    /// Springs — these specific values come from boring.notch's ContentView,
    /// which itself was tuned to feel like NotchNook. Don't change them
    /// without A/B-ing against the real apps.
    enum Spring {
        static let open  = (response: 0.42, damping: 0.8, blend: 0.0)
        static let close = (response: 0.45, damping: 1.0, blend: 0.0)
    }

    /// Computes the physical notch dimensions for a given screen. Falls back
    /// to a sensible default on Macs without a notch.
    @MainActor
    static func closedNotchSize(for screen: NSScreen?) -> CGSize {
        guard let screen else { return CGSize(width: 185, height: 32) }

        var notchHeight: CGFloat = screen.frame.maxY - screen.visibleFrame.maxY
        var notchWidth:  CGFloat = 185

        if let left  = screen.auxiliaryTopLeftArea?.width,
           let right = screen.auxiliaryTopRightArea?.width
        {
            // +4 to nudge our pill slightly past the camera bump (boring.notch trick).
            notchWidth = screen.frame.width - left - right + 4
        }

        if screen.safeAreaInsets.top > 0 {
            notchHeight = screen.safeAreaInsets.top
        }

        return CGSize(width: notchWidth, height: notchHeight)
    }

    /// Top-of-screen origin for the panel of the given size on the given screen.
    @MainActor
    static func windowOrigin(for screen: NSScreen, size: CGSize) -> NSPoint {
        NSPoint(
            x: screen.frame.origin.x + (screen.frame.width / 2) - (size.width / 2),
            y: screen.frame.origin.y + screen.frame.height - size.height
        )
    }
}
