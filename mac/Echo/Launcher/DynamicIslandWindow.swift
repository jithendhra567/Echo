import AppKit
import SwiftUI

/// Transparent NSPanel hosting the launcher search UI.
/// The island shape morphs entirely in SwiftUI — the window frame never changes.
///
/// Lifecycle:
///   Hidden at launch → appears only when the hotkey fires or status bar is clicked.
///   show()  : window appears → island springs in (isVisible) → expands (isExpanded)
///   hide()  : island collapses → fades out → orderOut after animation completes
///
/// Race-condition fix: `hideTask` is cancelled in show() so a rapid hide→show
/// sequence never lets the deferred orderOut() undo a subsequent show().
final class DynamicIslandWindow: NSPanel, NSWindowDelegate {
    let viewModel = LauncherViewModel()
    private let clipViewModel: ClipViewModel
    private let notchLayoutGuide: NotchLayoutGuide
    nonisolated(unsafe) private var topInsetObserver: NSObjectProtocol?
    private var previousApp: NSRunningApplication?
    private var localKeyMonitor: Any?
    private var hideTask: Task<Void, Never>?
    private(set) var isShowing = false

    static let windowSize = CGSize(width: 860, height: 600)

    init(clipViewModel: ClipViewModel, notchLayoutGuide: NotchLayoutGuide) {
        self.clipViewModel = clipViewModel
        self.notchLayoutGuide = notchLayoutGuide
        super.init(
            contentRect: NSRect(origin: .zero, size: Self.windowSize),
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        configure()
        contentView = NSHostingView(
            rootView: DynamicIslandView()
                .environment(viewModel)
                .environment(clipViewModel)
                .environment(viewModel.instantSearchSession)
        )
        viewModel.onDismiss      = { [weak self] in self?.hide() }
        viewModel.onLaunch       = { [weak self] in self?.hideAfterLaunch() }
        viewModel.onInstantSearchChanged = { [weak self] open in
            self?.applyInstantSearchLayout(open)
        }
        viewModel.clipVM         = clipViewModel

        topInsetObserver = NotificationCenter.default.addObserver(
            forName: .echoNotchTopInsetDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self, self.isShowing else { return }
            self.reposition()
        }
    }

    deinit {
        if let o = topInsetObserver { NotificationCenter.default.removeObserver(o) }
    }

    private func configure() {
        isFloatingPanel    = true
        level              = .floating
        backgroundColor    = .clear
        isOpaque           = false
        hasShadow          = false
        isMovableByWindowBackground = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        delegate           = self
        ignoresMouseEvents = true
        // Force dark appearance so all SwiftUI text renders white by default,
        // regardless of the user's system-wide light/dark mode setting.
        appearance = NSAppearance(named: .darkAqua)
    }

    // MARK: - Positioning

    func reposition() {
        guard let screen = NSScreen.main else { return }
        let size = frame.size
        let visible = screen.visibleFrame
        let x = screen.frame.midX - size.width / 2

        let y: CGFloat
        if viewModel.isInstantSearchOpen {
            let island = DynamicIslandView.instantSearchSize(for: screen)
            y = visible.midY - island.height / 2 - notchLayoutGuide.topInset * 0.35
        } else {
            let topFraction: CGFloat = 0.28
            y = visible.maxY - visible.height * topFraction - size.height - notchLayoutGuide.topInset
        }

        let clampedY = min(max(y, visible.minY), visible.maxY - size.height)
        setFrameOrigin(NSPoint(x: x, y: clampedY))
    }

    private func applyInstantSearchLayout(_ open: Bool) {
        guard let screen = NSScreen.main else { return }
        let oldFrame = frame
        let visible = screen.visibleFrame
        let islandPad = CGSize(width: 100, height: 100)

        let newSize: CGSize
        if open {
            let island = DynamicIslandView.instantSearchSize(for: screen)
            newSize = CGSize(width: island.width + islandPad.width, height: island.height + islandPad.height)
        } else {
            newSize = Self.windowSize
        }

        let newX = screen.frame.midX - newSize.width / 2
        let newY: CGFloat
        if open {
            // Grow from the center of the current launcher island on screen.
            let priorIslandH = DynamicIslandView.expandedHeight
            let priorCenterY = oldFrame.maxY - priorIslandH / 2
            newY = priorCenterY - newSize.height / 2
        } else {
            let topFraction: CGFloat = 0.28
            newY = visible.maxY - visible.height * topFraction - newSize.height - notchLayoutGuide.topInset
        }

        let clampedY = min(max(newY, visible.minY), visible.maxY - newSize.height)
        let targetFrame = NSRect(x: newX, y: clampedY, width: newSize.width, height: newSize.height)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.38
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 1.0, 0.36, 1.0)
            context.allowsImplicitAnimation = true
            animator().setFrame(targetFrame, display: true)
        }
    }

    // MARK: - Show / Hide

    func show() {
        guard !isShowing else { return }
        // Cancel any in-flight hide so its deferred orderOut won't fire.
        hideTask?.cancel()
        hideTask = nil

        previousApp = NSWorkspace.shared.frontmostApplication
        isShowing   = true
        viewModel.prepareForShow()
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(600))
            guard let self, self.isShowing else { return }
            self.clipViewModel.loadClips()
        }
        reposition()
        ignoresMouseEvents = false
        acceptsMouseMovedEvents = true   // needed to detect first move for hover-guard

        // Activate Echo so the panel can become key and accept keyboard input.
        NSApp.activate(ignoringOtherApps: true)
        orderFrontRegardless()
        makeKeyAndOrderFront(nil)

        // Single smooth scale + fade from the center of the island.
        // `isExpanded` is flipped in the same transaction so the content reveal
        // (gated on it via onChange) starts in lock-step with the open.
        withAnimation(.spring(response: 0.44, dampingFraction: 0.86)) {
            viewModel.isVisible  = true
            viewModel.isExpanded = true
        }
        setupKeyMonitor()
    }

    func hide() {
        guard isShowing else { return }
        isShowing = false
        tearDownKeyMonitor()

        // Fade out and scale back to the center — mirrors the open animation.
        withAnimation(.spring(response: 0.26, dampingFraction: 0.92)) {
            viewModel.isVisible  = false
            viewModel.isExpanded = false
        }

        hideTask?.cancel()
        hideTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(280))
            guard !Task.isCancelled else { return }
            self.ignoresMouseEvents = true
            self.orderOut(nil)
            self.previousApp?.activate(options: [])
            self.previousApp = nil
        }
    }

    func toggle() { isShowing ? hide() : show() }

    /// Hide without restoring focus to `previousApp` — used when launching an app
    /// so the launched app keeps focus instead of the prior app stealing it back.
    func hideAfterLaunch() {
        previousApp = nil
        hide()
    }

    // MARK: - Keyboard navigation

    private func setupKeyMonitor() {
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let code = event.keyCode
            // 48 = Tab, 53 = Escape, 36 = Return, 76 = Numpad Enter, 125 = ↓, 126 = ↑
            let consume = code == 48 || code == 53 || code == 36 || code == 76 || code == 125 || code == 126
            Task { @MainActor [weak self] in
                guard let self else { return }
                switch code {
                case 48:      self.viewModel.switchPanel()
                case 53:
                    if self.viewModel.isInstantSearchOpen {
                        self.viewModel.closeInstantSearch()
                    } else {
                        self.hide()
                    }
                case 36, 76:
                    if event.modifierFlags.contains(.shift) {
                        self.viewModel.searchGoogle()
                    } else {
                        self.viewModel.confirmSelected()
                    }
                case 125:     self.viewModel.selectNext()
                case 126:     self.viewModel.selectPrevious()
                default:      break
                }
            }
            return consume ? nil : event
        }
    }

    private func tearDownKeyMonitor() {
        if let m = localKeyMonitor { NSEvent.removeMonitor(m); localKeyMonitor = nil }
    }

    // MARK: - Click-outside dismiss

    func windowDidResignKey(_ notification: Notification) {
        guard isShowing else { return }
        hide()
    }

    override func mouseDown(with event: NSEvent) {
        let loc = event.locationInWindow
        let iw: CGFloat
        let ih: CGFloat
        if viewModel.isInstantSearchOpen {
            let size = DynamicIslandView.instantSearchSize(for: NSScreen.main)
            iw = size.width
            ih = size.height
        } else {
            iw = DynamicIslandView.expandedWidth
            ih = DynamicIslandView.expandedHeight
        }
        let win = frame.size
        let ix = (win.width - iw) / 2
        let iy = viewModel.isInstantSearchOpen
            ? (win.height - ih) / 2
            : win.height - ih
        let islandRect = CGRect(x: ix, y: iy, width: iw, height: ih)

        if islandRect.contains(loc) {
            super.mouseDown(with: event)
        } else {
            hide()
        }
    }

    override func mouseMoved(with event: NSEvent) {
        if viewModel.ignoreHover {
            viewModel.ignoreHover = false
            acceptsMouseMovedEvents = false  // stop generating events once guard is lifted
        }
        super.mouseMoved(with: event)
    }

    override var canBecomeKey: Bool  { true  }
    override var canBecomeMain: Bool { false }
}
