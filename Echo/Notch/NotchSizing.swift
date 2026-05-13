import AppKit
import CoreGraphics

/// Central sizing constants — single source of truth for the entire notch
/// subsystem. Mirrors `sizing/matters.swift` in TheBoredTeam/boring.notch.
enum NotchSizing {
    /// Padding around the window to make room for shadow / overshoot.
    static let shadowPadding: CGFloat = 20

    /// The exact frame the pill occupies when expanded (height fits clock +
    /// mirror column, tab strip, and insets).
    static let openSize = CGSize(width: 620, height: 272)

    /// Padding from the top of the open pill to content (clears hardware notch / curve).
    static let openContentTopInset: CGFloat = 22

    /// Side inset for open module content (clock / tray / music).
    static let openContentHorizontalInset: CGFloat = 28

    /// Horizontal space between clock, calendar, and mirror in `ClockOpenView`.
    static let openClockInterColumnSpacing: CGFloat = 14

    /// Expanded pill height plus shadow band and clearance — `NotchLayoutGuide` / launcher use this.
    static var expandedPillHeight: CGFloat {
        openSize.height + shadowPadding + 16
    }

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

    /// Springs — `open` uses a bit less damping than boring.notch so width /
    /// height / radii overshoot slightly then settle (bounce without scaling).
    enum Spring {
        static let open  = (response: 0.42, damping: 0.72, blend: 0.0)
        static let close = (response: 0.45, damping: 1.0, blend: 0.0)
    }

    /// Minimum horizontal gap (pt) between left and right auxiliary regions for
    /// us to treat the screen as having a real menu-bar “island” / notch.
    private static let minCenterIslandWidth: CGFloat = 50

    /// Closed pill height on displays **without** a hardware notch (points).
    private static let flatPanelClosedNotchHeight: CGFloat = 4

    /// `true` when the system reports split auxiliary menu-bar regions flanking
    /// a center camera housing (notched MacBook). Typical HDMI / Thunderbolt
    /// panels omit `auxiliaryTopLeftArea` / `auxiliaryTopRightArea`.
    @MainActor
    static func hasMenuBarNotch(_ screen: NSScreen) -> Bool {
        guard let left = screen.auxiliaryTopLeftArea?.width,
              let right = screen.auxiliaryTopRightArea?.width,
              left > 0,
              right > 0
        else { return false }
        let w = screen.frame.width
        return left + right < w - minCenterIslandWidth
    }

    /// The screen whose top center hosts the notch panel — follows the **menu
    /// bar** (`NSScreen.main`), so the pill appears on an external monitor when
    /// that display is primary.
    @MainActor
    static func targetScreenForPanel() -> NSScreen {
        NSScreen.main ?? NSScreen.screens.first!
    }

    /// Geometry suggests native fullscreen (or auto-hidden menu bar): almost
    /// full-height `visibleFrame` and little top chrome reserved.
    @MainActor
    static func looksLikeFullscreenMenuHidden(_ screen: NSScreen) -> Bool {
        guard !hasMenuBarNotch(screen) else { return false }
        let topReserved = screen.frame.maxY - screen.visibleFrame.maxY
        let nearlyFullHeight = screen.visibleFrame.height >= screen.frame.height * 0.85
        return topReserved < 26 && nearlyFullHeight
    }

    /// Top-edge band (pt) where the pointer sits while revealing the menu bar in
    /// native fullscreen on a flat panel.
    static let menuRevealTopSlop: CGFloat = 40

    /// How long the cursor must stay in `menuRevealTopSlop` before we show the
    /// pill on a **non-notched** display in fullscreen.
    static let menuRevealHoldDuration: TimeInterval = 0.48

    /// Cursor in the top strip of `screen` where the user reveals the menu bar
    /// while in native fullscreen (macOS hides the bar until the pointer hits the top).
    @MainActor
    static func mouseNearTopMenuReveal(on screen: NSScreen, slop: CGFloat = menuRevealTopSlop) -> Bool {
        let p = NSEvent.mouseLocation
        guard NSMouseInRect(p, screen.frame, false) else { return false }
        return p.y >= screen.frame.maxY - slop
    }

    /// **Non-notched displays:** the pill stays available on normal desktops
    /// (e.g. external monitor). In native fullscreen with an auto-hidden menu
    /// bar, hide until the user **holds** the cursor in the top reveal band for
    /// `menuRevealHoldDuration`, or until the system reserves a visible menu strip
    /// (`topReserved >= 18`). `sessionRevealed` keeps the pill visible after a
    /// successful hold until fullscreen ends. **Hardware-notched** screens are
    /// never suppressed by this rule.
    @MainActor
    static func shouldSuppressForExternalFullscreen(
        _ screen: NSScreen,
        menuRevealHoldSatisfied: Bool,
        sessionRevealed: Bool
    ) -> Bool {
        guard !hasMenuBarNotch(screen) else { return false }

        // Flat panel + normal desktop: do not suppress (user can reach the notch).
        guard looksLikeFullscreenMenuHidden(screen) else { return false }

        let topReserved = screen.frame.maxY - screen.visibleFrame.maxY

        // Menu strip is visibly back — show without requiring a hold.
        if topReserved >= 18 { return false }
        if sessionRevealed { return false }
        return !menuRevealHoldSatisfied
    }

    /// While true, poll layout so we notice pointer moves to the top (menu reveal).
    @MainActor
    static func needsMenuRevealPolling(for screen: NSScreen) -> Bool {
        looksLikeFullscreenMenuHidden(screen)
    }

    /// Computes the physical notch dimensions for a given screen. Falls back
    /// to a sensible default on Macs without a notch.
    ///
    /// - Parameter flatUseCompactStripHeight: On **non-notched** screens only.
    ///   When `true` (idle tray: no drag, no files), the closed height is
    ///   `flatPanelClosedNotchHeight`. When `false`, uses the normal menu-bar /
    ///   safe-area height so dragging or shelved files keep a readable strip.
    @MainActor
    static func closedNotchSize(for screen: NSScreen?, flatUseCompactStripHeight: Bool = true) -> CGSize {
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

        if !hasMenuBarNotch(screen), flatUseCompactStripHeight {
            notchHeight = flatPanelClosedNotchHeight
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
