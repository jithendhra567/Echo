import AppKit
import SwiftUI

/// Fixed-size `NSPanel` that hosts `NotchView`.
///
/// **The window never resizes.** All visual state changes happen inside
/// SwiftUI via spring animation. Resizing through `NSWindow.setFrame`
/// round-trips to WindowServer at every step and is the #1 cause of lag in
/// pill-style notch UIs.
///
/// We do **not** override `hitTest` either. The SwiftUI tree itself decides
/// what's hit-testable: the pill uses `.contentShape(Rectangle())`, the
/// surrounding canvas uses `Color.clear.allowsHitTesting(false)`. NSHostingView
/// honors that and returns nil for points outside the pill, so the menu bar
/// stays clickable.
final class NotchPanel: NSPanel {

    let viewModel = NotchViewModel()
    private let dragMon = GlobalDragMonitor()
    /// Observer tokens — `nonisolated(unsafe)` so `deinit` can remove them.
    nonisolated(unsafe) private var screenChangeObserver: NSObjectProtocol?
    nonisolated(unsafe) private var activeSpaceObserver: NSObjectProtocol?
    nonisolated(unsafe) private var activateAppObserver: NSObjectProtocol?
    /// Poller for menu-bar-at-top in fullscreen — `nonisolated(unsafe)` for `deinit`.
    nonisolated(unsafe) private var fullscreenRevealTimer: Timer?

    /// Cursor entered the top reveal band at this time (flat panel + fullscreen).
    private var menuRevealHoverStart: Date?
    /// After a successful top-edge hold, stay visible until fullscreen ends.
    private var flatFullscreenRevealLatched = false

    init() {
        let size = NotchSizing.windowSize
        let screen = NotchSizing.targetScreenForPanel()
        let origin = NotchSizing.windowOrigin(for: screen, size: size)
        let frame = NSRect(origin: origin, size: size)

        super.init(
            contentRect: frame,
            styleMask:   [.borderless, .nonactivatingPanel, .utilityWindow, .hudWindow],
            backing:     .buffered,
            defer:       false
        )

        configure()

        syncClosedNotchSize(with: screen)

        let hosting = NSHostingView(rootView: NotchView().environment(viewModel))
        hosting.sizingOptions = []
        contentView = hosting

        viewModel.tray.onContentChanged = { [weak self] in
            guard let self else { return }
            self.syncClosedNotchSize(with: NotchSizing.targetScreenForPanel())
            self.contentView?.needsLayout = true
            self.contentView?.layoutSubtreeIfNeeded()
        }

        setupDragMonitor()
    }

    deinit {
        if let screenChangeObserver {
            NotificationCenter.default.removeObserver(screenChangeObserver)
        }
        if let activeSpaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activeSpaceObserver)
        }
        if let activateAppObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activateAppObserver)
        }
        fullscreenRevealTimer?.invalidate()
        fullscreenRevealTimer = nil
    }

    func start() {
        viewModel.start()
        applyScreenLayout()

        if let screenChangeObserver {
            NotificationCenter.default.removeObserver(screenChangeObserver)
        }
        screenChangeObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.applyScreenLayout()
        }

        if let activeSpaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activeSpaceObserver)
        }
        activeSpaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.applyScreenLayout()
        }

        if let activateAppObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activateAppObserver)
        }
        activateAppObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.applyScreenLayout()
        }
    }

    /// Repositions on `NSScreen.main` (external or built-in). On displays
    /// **without** a hardware notch, fullscreen with an auto-hidden menu bar
    /// hides the pill until the user **holds** the cursor at the top edge
    /// (menu-bar reveal). Windowed desktop use keeps the notch visible. Notched
    /// Macs are unchanged.
    private func applyScreenLayout() {
        let screen = NotchSizing.targetScreenForPanel()
        updateFullscreenRevealTimer(for: screen)

        let holdSatisfied = updateFlatFullscreenMenuRevealState(for: screen)

        if NotchSizing.shouldSuppressForExternalFullscreen(
            screen,
            menuRevealHoldSatisfied: holdSatisfied,
            sessionRevealed: flatFullscreenRevealLatched
        ) {
            suppressNotchPanel()
            return
        }

        ignoresMouseEvents = false
        alphaValue = 1
        let size = NotchSizing.windowSize
        let origin = NotchSizing.windowOrigin(for: screen, size: size)
        setFrame(NSRect(origin: origin, size: size), display: true, animate: false)
        syncClosedNotchSize(with: screen)
        orderFrontRegardless()
        contentView?.needsLayout = true
        contentView?.layoutSubtreeIfNeeded()
    }

    /// Flat panels use a 4pt strip only when the tray is idle; drag / files use full height.
    private func syncClosedNotchSize(with screen: NSScreen) {
        let compactStrip =
            !NotchSizing.hasMenuBarNotch(screen)
            && !viewModel.tray.isDragInFlight
            && viewModel.tray.files.isEmpty
        viewModel.closedNotchSize = NotchSizing.closedNotchSize(
            for: screen,
            flatUseCompactStripHeight: compactStrip
        )
    }

    /// Low-rate timer while fullscreen may be hiding the menu bar — `NSEvent`
    /// does not post notifications, so we re-check layout on mouse moves to top.
    private func updateFullscreenRevealTimer(for screen: NSScreen) {
        let poll = NotchSizing.needsMenuRevealPolling(for: screen)
        if poll {
            guard fullscreenRevealTimer == nil else { return }
            let t = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
                DispatchQueue.main.async { self?.applyScreenLayout() }
            }
            RunLoop.main.add(t, forMode: .common)
            fullscreenRevealTimer = t
        } else {
            fullscreenRevealTimer?.invalidate()
            fullscreenRevealTimer = nil
        }
    }

    /// Tracks dwell at the top edge on non-notched fullscreen; updates
    /// `flatFullscreenRevealLatched`. Returns whether the hold duration is met.
    private func updateFlatFullscreenMenuRevealState(for screen: NSScreen) -> Bool {
        if NotchSizing.hasMenuBarNotch(screen) {
            menuRevealHoverStart = nil
            flatFullscreenRevealLatched = false
            return false
        }
        if !NotchSizing.looksLikeFullscreenMenuHidden(screen) {
            menuRevealHoverStart = nil
            flatFullscreenRevealLatched = false
            return false
        }

        if NotchSizing.mouseNearTopMenuReveal(on: screen) {
            if menuRevealHoverStart == nil {
                menuRevealHoverStart = Date()
            }
        } else {
            menuRevealHoverStart = nil
        }

        let holdMet: Bool
        if let start = menuRevealHoverStart {
            holdMet = Date().timeIntervalSince(start) >= NotchSizing.menuRevealHoldDuration
        } else {
            holdMet = false
        }
        if holdMet {
            flatFullscreenRevealLatched = true
        }
        return holdMet
    }

    private func suppressNotchPanel() {
        orderOut(nil)
        alphaValue = 0
        ignoresMouseEvents = true
    }

    private func configure() {
        isFloatingPanel             = true
        level                       = .mainMenu + 3
        backgroundColor             = .clear
        isOpaque                    = false
        hasShadow                   = false
        titleVisibility             = .hidden
        titlebarAppearsTransparent  = true
        isMovableByWindowBackground = false
        isMovable                   = false
        collectionBehavior          = [.fullScreenAuxiliary, .stationary, .canJoinAllSpaces, .ignoresCycle]
        appearance                  = NSAppearance(named: .darkAqua)
    }

    // MARK: - Pill rect (used only for drag-halo detection)

    /// Rect occupied by the open pill, in the hosting view's coordinate
    /// space. The halo around this rect is what triggers tray pre-open during
    /// a global drag.
    private func openPillRect(in bounds: NSRect) -> NSRect {
        let w = NotchSizing.openSize.width
        let h = NotchSizing.openSize.height
        return NSRect(x: bounds.midX - w / 2,
                      y: bounds.maxY - h,
                      width:  w,
                      height: h)
    }

    // MARK: - Drag wiring

    private var lastDragTick: TimeInterval = 0

    private func setupDragMonitor() {
        dragMon.onDragBegan = { [weak self] in
            self?.viewModel.tray.dragBegan()
        }
        dragMon.onDragMoved = { [weak self] screenPt in
            guard let self else { return }

            // Throttle to ~60 Hz. `leftMouseDragged` fires at display refresh
            // rate; halo math + state branches don't need to run more than that.
            let now = CACurrentMediaTime()
            if now - self.lastDragTick < (1.0 / 60.0) { return }
            self.lastDragTick = now

            guard let content = self.contentView else { return }

            // NSView.convert(_:from: nil) treats the source as WINDOW
            // coordinates, not screen. `screenPt` is NSEvent.mouseLocation
            // (screen-space), so we have to go screen → window → view.
            let windowPt = self.convertPoint(fromScreen: screenPt)
            let local    = content.convert(windowPt, from: nil)

            let pill = self.openPillRect(in: content.bounds)
            // Halo: a generous radius around the open pill triggers pre-open.
            let halo = pill.insetBy(dx: -60, dy: -50)
            if halo.contains(local) {
                self.viewModel.open()           // idempotent — cheap no-op when already open
            }
        }
        dragMon.onDragEnded = { [weak self] in
            self?.viewModel.tray.dragEnded()
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(220))
                guard let self else { return }
                if !self.viewModel.anyModuleActive && !self.viewModel.isHovering {
                    self.viewModel.close()
                }
            }
        }
        dragMon.start()
    }

    override var canBecomeKey:  Bool { false }
    override var canBecomeMain: Bool { false }
}
