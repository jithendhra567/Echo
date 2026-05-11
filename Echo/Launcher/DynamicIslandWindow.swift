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
    private var previousApp: NSRunningApplication?
    private var localKeyMonitor: Any?
    private var hideTask: Task<Void, Never>?
    private(set) var isShowing = false

    static let windowSize = CGSize(width: 860, height: 600)

    init(clipViewModel: ClipViewModel) {
        self.clipViewModel = clipViewModel
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
        )
        viewModel.onDismiss = { [weak self] in self?.hide() }
        viewModel.onLaunch  = { [weak self] in self?.hideAfterLaunch() }
        viewModel.clipVM    = clipViewModel
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
        let x = screen.frame.midX - Self.windowSize.width / 2
        // ~28 % from top of visible area — Spotlight-style
        let y = screen.visibleFrame.maxY - screen.visibleFrame.height * 0.28 - Self.windowSize.height
        setFrameOrigin(NSPoint(x: x, y: max(y, screen.visibleFrame.minY)))
    }

    // MARK: - Show / Hide

    func show() {
        guard !isShowing else { return }
        // Cancel any in-flight hide so its deferred orderOut won't fire.
        hideTask?.cancel()
        hideTask = nil

        previousApp = NSWorkspace.shared.frontmostApplication
        isShowing   = true
        viewModel.reset()          // resets isVisible=false, isExpanded=false
        clipViewModel.loadClips()  // refresh clipboard history
        reposition()
        ignoresMouseEvents = false
        acceptsMouseMovedEvents = true   // needed to detect first move for hover-guard

        // Activate Echo so the panel can become key and accept keyboard input.
        NSApp.activate(ignoringOtherApps: true)
        orderFrontRegardless()
        makeKeyAndOrderFront(nil)

        withAnimation(.spring(response: 0.22, dampingFraction: 0.82)) {
            viewModel.isVisible = true
        }
        withAnimation(.spring(response: 0.34, dampingFraction: 0.78)) {
            viewModel.isExpanded = true
        }
        setupKeyMonitor()
    }

    func hide() {
        guard isShowing else { return }
        isShowing = false
        tearDownKeyMonitor()

        // Fade out and collapse simultaneously — no lingering pill visible.
        withAnimation(.spring(response: 0.22, dampingFraction: 0.88)) {
            viewModel.isVisible  = false
            viewModel.isExpanded = false
        }

        hideTask?.cancel()
        hideTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(270))
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
                case 53:      self.hide()
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
        let iw: CGFloat = viewModel.isExpanded ? DynamicIslandView.expandedWidth : DynamicIslandView.pillWidth
        let ih: CGFloat = viewModel.isExpanded ? DynamicIslandView.expandedHeight : DynamicIslandView.pillHeight
        let ix = (Self.windowSize.width - iw) / 2
        let iy = Self.windowSize.height - ih
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
