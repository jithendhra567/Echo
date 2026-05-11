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
    /// Observer token — `nonisolated(unsafe)` so `deinit` can remove it.
    nonisolated(unsafe) private var screenChangeObserver: NSObjectProtocol?

    init() {
        let size = NotchSizing.windowSize
        let screen = NotchSizing.preferredNotchScreen()
            ?? NSScreen.main
            ?? NSScreen.screens.first!
        let origin = NotchSizing.windowOrigin(for: screen, size: size)
        let frame = NSRect(origin: origin, size: size)

        super.init(
            contentRect: frame,
            styleMask:   [.borderless, .nonactivatingPanel, .utilityWindow, .hudWindow],
            backing:     .buffered,
            defer:       false
        )

        configure()

        viewModel.closedNotchSize = NotchSizing.closedNotchSize(for: screen)

        let hosting = NSHostingView(rootView: NotchView().environment(viewModel))
        hosting.sizingOptions = []
        contentView = hosting

        setupDragMonitor()
    }

    deinit {
        if let screenChangeObserver {
            NotificationCenter.default.removeObserver(screenChangeObserver)
        }
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
    }

    /// Repositions on the **notched** built-in display when available; hides the
    /// panel on plain external / desktop monitors so nothing draws over the tab bar.
    private func applyScreenLayout() {
        guard let screen = NotchSizing.preferredNotchScreen() else {
            hideForNonNotchedDisplays()
            return
        }

        ignoresMouseEvents = false
        alphaValue = 1
        let size = NotchSizing.windowSize
        let origin = NotchSizing.windowOrigin(for: screen, size: size)
        setFrame(NSRect(origin: origin, size: size), display: true, animate: false)
        viewModel.closedNotchSize = NotchSizing.closedNotchSize(for: screen)
        orderFrontRegardless()
        contentView?.needsLayout = true
        contentView?.layoutSubtreeIfNeeded()
    }

    /// No eligible notched screen (e.g. clamshell + external only) — remove from
    /// screen list and ignore mouse so other apps receive clicks.
    private func hideForNonNotchedDisplays() {
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
