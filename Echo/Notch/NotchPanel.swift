import AppKit
import SwiftUI

/// Fixed-size `NSPanel` that hosts `NotchView`.
///
/// **Click-through** is achieved by keeping `ignoresMouseEvents = true` whenever
/// the cursor is outside the pill. `ignoresMouseEvents = true` is a hard OS
/// guarantee — the window server skips our window entirely and routes the event
/// to whatever is underneath, regardless of window level. We track cursor
/// position via a global `mouseMoved` / `leftMouseDragged` monitor (fires when
/// our window is transparent) and a local monitor (fires when we temporarily
/// accept events while the pill is active).
final class NotchPanel: NSPanel {

    let viewModel = NotchViewModel()
    private let layoutGuide: NotchLayoutGuide
    private let dragMon = GlobalDragMonitor()
    nonisolated(unsafe) private var screenChangeObserver: NSObjectProtocol?
    nonisolated(unsafe) private var activeSpaceObserver:  NSObjectProtocol?
    nonisolated(unsafe) private var activateAppObserver:  NSObjectProtocol?
    nonisolated(unsafe) private var fullscreenRevealTimer: Timer?

    /// Global monitor — fires while `ignoresMouseEvents = true` (cursor anywhere).
    nonisolated(unsafe) private var globalCursorMonitor: Any?
    /// Local monitor — fires while `ignoresMouseEvents = false` (pill active).
    nonisolated(unsafe) private var localCursorMonitor:  Any?

    private var menuRevealHoverStart:      Date?
    private var flatFullscreenRevealLatched = false

    init(layoutGuide: NotchLayoutGuide) {
        self.layoutGuide = layoutGuide
        let size   = NotchSizing.windowSize
        let screen = NotchSizing.targetScreenForPanel()
        let origin = NotchSizing.windowOrigin(for: screen, size: size)

        super.init(
            contentRect: NSRect(origin: origin, size: size),
            styleMask:   [.borderless, .nonactivatingPanel, .utilityWindow, .hudWindow],
            backing:     .buffered,
            defer:       false
        )

        configure()
        syncClosedNotchSize(with: screen)

        let hosting = PillHostingView(
            rootView: NotchView()
                .environment(viewModel)
                .environment(layoutGuide)
        )
        hosting.sizingOptions = []
        contentView = hosting
        hosting.viewModel = viewModel

        viewModel.tray.onContentChanged = { [weak self] in
            guard let self else { return }
            self.syncClosedNotchSize(with: NotchSizing.targetScreenForPanel())
            self.contentView?.needsLayout = true
            self.contentView?.layoutSubtreeIfNeeded()
        }

        setupDragMonitor()
        setupCursorTracking()
    }

    deinit {
        [screenChangeObserver, activeSpaceObserver, activateAppObserver]
            .compactMap { $0 }
            .forEach { NotificationCenter.default.removeObserver($0) }
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        fullscreenRevealTimer?.invalidate()
        if let m = globalCursorMonitor { NSEvent.removeMonitor(m) }
        if let m = localCursorMonitor  { NSEvent.removeMonitor(m) }
    }

    func start() {
        applyScreenLayout()

        screenChangeObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in self?.applyScreenLayout() }

        activeSpaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil, queue: .main
        ) { [weak self] _ in self?.applyScreenLayout() }

        activateAppObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil, queue: .main
        ) { [weak self] _ in self?.applyScreenLayout() }
    }

    // MARK: - Cursor tracking (ignoresMouseEvents toggle)

    private func setupCursorTracking() {
        // Global: fires when ignoresMouseEvents = true (cursor over other apps / our transparent window)
        globalCursorMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.mouseMoved, .leftMouseDragged, .leftMouseDown]
        ) { [weak self] _ in
            DispatchQueue.main.async { self?.updateMousePassthrough() }
        }

        // Local: fires when ignoresMouseEvents = false (pill is active, cursor in our window)
        localCursorMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.mouseMoved, .mouseExited]
        ) { [weak self] event in
            DispatchQueue.main.async { self?.updateMousePassthrough() }
            return event
        }
    }

    /// Computes the current pill rect in WINDOW coordinates (AppKit: y=0 at bottom).
    private func currentPillRect() -> NSRect {
        let winW  = NotchSizing.windowSize.width
        let winH  = NotchSizing.windowSize.height
        let pillW: CGFloat
        let pillH: CGFloat

        if viewModel.notchState == .open {
            pillW = viewModel.activeModule.openExpandedWidth
            pillH = NotchSizing.openSize.height
        } else {
            let mod   = viewModel.activeModule
            let extra = mod.isActive ? mod.closedExtraWidth : 0
            pillW     = viewModel.closedNotchSize.width + extra
            pillH     = viewModel.closedNotchSize.height
        }

        return NSRect(
            x:      winW / 2 - pillW / 2,
            y:      winH - pillH,
            width:  pillW,
            height: pillH
        )
    }

    private func updateMousePassthrough() {
        let screenPt = NSEvent.mouseLocation
        let windowPt = convertPoint(fromScreen: screenPt)

        // Small inset buffer so cursor touching the edge still registers.
        let pillRect   = currentPillRect().insetBy(dx: -4, dy: -4)
        let overPill   = pillRect.contains(windowPt)
        let dragActive = viewModel.tray.isDragInFlight

        // Accept events only when cursor is directly over the pill or a drag is
        // in flight. currentPillRect() already returns open-pill bounds when
        // notchState == .open, so the open-state margin outside the pill stays
        // transparent — clicks reach Chrome tabs / Xcode windows behind us.
        let shouldAccept = overPill || dragActive
        let newIgnore    = !shouldAccept

        if ignoresMouseEvents != newIgnore {
            ignoresMouseEvents = newIgnore
        }
    }

    // MARK: - Screen layout

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

        alphaValue = 1
        let size   = NotchSizing.windowSize
        let origin = NotchSizing.windowOrigin(for: screen, size: size)
        setFrame(NSRect(origin: origin, size: size), display: true, animate: false)
        syncClosedNotchSize(with: screen)
        orderFrontRegardless()
        contentView?.needsLayout = true
        contentView?.layoutSubtreeIfNeeded()
        layoutGuide.setTopInset(viewModel.notchState == .open ? NotchSizing.expandedPillHeight : 0)
        // Let cursor tracking decide ignoresMouseEvents — do NOT force it here.
        updateMousePassthrough()
    }

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
            if menuRevealHoverStart == nil { menuRevealHoverStart = Date() }
        } else {
            menuRevealHoverStart = nil
        }
        let holdMet: Bool
        if let start = menuRevealHoverStart {
            holdMet = Date().timeIntervalSince(start) >= NotchSizing.menuRevealHoldDuration
        } else {
            holdMet = false
        }
        if holdMet { flatFullscreenRevealLatched = true }
        return holdMet
    }

    private func suppressNotchPanel() {
        layoutGuide.setTopInset(0)
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
        ignoresMouseEvents          = true  // default: fully transparent until cursor enters pill
    }

    // MARK: - Pill rect for drag-halo detection

    private func openPillRect(in bounds: NSRect) -> NSRect {
        let w = NotchSizing.openSize.width
        let h = NotchSizing.openSize.height
        return NSRect(x: bounds.midX - w / 2, y: bounds.maxY - h, width: w, height: h)
    }

    // MARK: - Drag monitor

    private var lastDragTick: TimeInterval = 0

    private func setupDragMonitor() {
        dragMon.onDragBegan = { [weak self] in
            self?.viewModel.tray.dragBegan()
        }
        dragMon.onDragMoved = { [weak self] screenPt in
            guard let self else { return }
            let now = CACurrentMediaTime()
            if now - self.lastDragTick < (1.0 / 60.0) { return }
            self.lastDragTick = now

            guard let content = self.contentView else { return }
            let windowPt = self.convertPoint(fromScreen: screenPt)
            let local    = content.convert(windowPt, from: nil)
            let halo     = self.openPillRect(in: content.bounds).insetBy(dx: -60, dy: -50)
            if halo.contains(local) {
                self.viewModel.open()
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

// MARK: - Hosting view (secondary hit-test guard for transparent margins)

/// When `ignoresMouseEvents = false` and the pill is open, events in the
/// transparent shadow-padding margins around the pill would be consumed by our
/// window. This secondary guard returns nil for those margin areas so they also
/// pass through, consistent with the ignoresMouseEvents toggle logic.
private final class PillHostingView<C: View>: NSHostingView<C> {
    weak var viewModel: NotchViewModel?

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let vm = viewModel else { return super.hitTest(point) }
        guard pillRect(vm: vm).contains(point) else { return nil }
        return super.hitTest(point)
    }

    private func pillRect(vm: NotchViewModel) -> NSRect {
        let winW  = NotchSizing.windowSize.width
        let winH  = NotchSizing.windowSize.height
        let pillW: CGFloat
        let pillH: CGFloat

        if vm.notchState == .open {
            pillW = vm.activeModule.openExpandedWidth
            pillH = NotchSizing.openSize.height
        } else {
            let mod   = vm.activeModule
            let extra = mod.isActive ? mod.closedExtraWidth : 0
            pillW     = vm.closedNotchSize.width + extra
            pillH     = vm.closedNotchSize.height
        }

        return NSRect(
            x: winW / 2 - pillW / 2,
            y: winH - pillH,
            width:  pillW,
            height: pillH
        )
    }
}
