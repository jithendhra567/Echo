import AppKit
import SwiftUI

// MARK: - Presentation state (SwiftUI-driven slide)

@Observable
final class ClipboardPanelPresentation {
    var isPresented = false
}

/// Hosts the clipboard UI and slides it from below the dock via SwiftUI offset.
/// The window frame never moves — only the content animates, which avoids AppKit
/// `animator().setFrame` getting stuck on transparent NSPanels.
private struct ClipboardPanelRoot: View {
    @Environment(ClipboardPanelPresentation.self) private var presentation
    let viewModel: ClipViewModel

    static let panelHeight: CGFloat = 282
    static let slideDistance: CGFloat = 300

    var body: some View {
        Color.clear
            .overlay(alignment: .bottom) {
                ClipDashboardView()
                    .environment(viewModel)
                    .frame(height: Self.panelHeight)
                    .offset(y: presentation.isPresented ? 0 : Self.slideDistance)
                    .animation(
                        presentation.isPresented
                            ? .easeOut(duration: 0.42)
                            : .easeIn(duration: 0.30),
                        value: presentation.isPresented
                    )
            }
    }
}

// MARK: - Panel

/// A non-activating floating NSPanel that slides up from the bottom of the screen.
/// "Non-activating" means the previously focused app (e.g. VS Code) remains key,
/// enabling seamless drag-and-drop out of the panel.
final class ClipboardPanel: NSPanel {
    private(set) var isShowing = false
    private var localKeyMonitor: Any?
    private var scrollMonitor: Any?
    private var dragMouseMonitor: Any?
    private var hideTask: DispatchWorkItem?
    private let presentation = ClipboardPanelPresentation()
    private let viewModel: ClipViewModel

    init(viewModel: ClipViewModel) {
        self.viewModel = viewModel
        super.init(
            contentRect: .zero,
            styleMask: [.nonactivatingPanel, .fullSizeContentView, .borderless],
            backing: .buffered,
            defer: false
        )
        configure()
        let hosting = NSHostingView(
            rootView: ClipboardPanelRoot(viewModel: viewModel)
                .environment(presentation)
        )
        hosting.wantsLayer = true
        contentView = hosting
    }

    private func configure() {
        isFloatingPanel      = true
        level                = .floating
        backgroundColor      = .clear
        isOpaque             = false
        hasShadow            = false
        isMovableByWindowBackground = false
        collectionBehavior   = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        titleVisibility      = .hidden
        titlebarAppearsTransparent = true
    }

    // MARK: - Layout

    /// Fixed window frame: tall enough to hold the panel plus off-screen slide room below.
    private func windowFrame(for screen: NSScreen) -> NSRect {
        let vis = screen.visibleFrame
        let w = vis.width - 40
        let h = ClipboardPanelRoot.panelHeight + ClipboardPanelRoot.slideDistance
        let x = vis.minX + 20
        // Window bottom aligns with the panel's resting bottom edge.
        let y = vis.minY + 12
        return NSRect(x: x, y: y, width: w, height: h)
    }

    // MARK: - Show / Hide

    func show() {
        guard !isShowing, let screen = NSScreen.main else { return }
        hideTask?.cancel()
        hideTask = nil

        presentation.isPresented = false
        setFrame(windowFrame(for: screen), display: true)
        isShowing = true
        orderFrontRegardless()
        makeKey()
        setupKeyMonitor()
        setupScrollMonitor()
        setupDragMouseMonitor()

        DispatchQueue.main.async { [weak self] in
            guard let self, self.isShowing else { return }
            self.presentation.isPresented = true
        }

        // Load first page in the background — panel opens instantly with any cached clips.
        viewModel.loadPanelFirstPage()
    }

    func hide() {
        guard isShowing else { return }
        hideTask?.cancel()

        isShowing = false
        tearDownKeyMonitor()
        tearDownScrollMonitor()
        tearDownDragMouseMonitor()
        presentation.isPresented = false

        let work = DispatchWorkItem { [weak self] in
            guard let self, !self.isShowing else { return }
            self.orderOut(nil)
        }
        hideTask = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.32, execute: work)
    }

    func toggle() { isShowing ? hide() : show() }

    // MARK: - Keyboard handling

    /// Local monitor catches Escape while Echo is the key app (the global
    /// monitor in `AppDelegate` only fires for events sent to other apps).
    private func setupKeyMonitor() {
        if let m = localKeyMonitor { NSEvent.removeMonitor(m); localKeyMonitor = nil }
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53 else { return event }  // 53 = Escape
            self?.hide()
            return nil
        }
    }

    private func tearDownKeyMonitor() {
        if let m = localKeyMonitor { NSEvent.removeMonitor(m); localKeyMonitor = nil }
    }

    // MARK: - Vertical wheel → horizontal scroll

    private func setupScrollMonitor() {
        tearDownScrollMonitor()
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self, self.isShowing else { return event }
            return self.handleScrollWheel(event) ? nil : event
        }
    }

    private func tearDownScrollMonitor() {
        if let m = scrollMonitor { NSEvent.removeMonitor(m); scrollMonitor = nil }
    }

    /// Redirects vertical trackpad/wheel movement to the horizontal clip scroller.
    private func handleScrollWheel(_ event: NSEvent) -> Bool {
        guard let contentView else { return false }
        let localPoint = contentView.convert(event.locationInWindow, from: nil)
        guard contentView.bounds.contains(localPoint),
              let hit = contentView.hitTest(localPoint),
              !isTextInput(hit)
        else { return false }

        var view: NSView? = hit
        while let current = view {
            if let scrollView = current as? NSScrollView,
               let doc = scrollView.documentView,
               doc.frame.width > scrollView.contentView.bounds.width {
                return scrollHorizontally(scrollView: scrollView, document: doc, event: event)
            }
            view = current.superview
        }
        return false
    }

    private func scrollHorizontally(scrollView: NSScrollView, document: NSView, event: NSEvent) -> Bool {
        let vertical = event.hasPreciseScrollingDeltas
            ? event.scrollingDeltaY
            : CGFloat(event.deltaY) * 8
        let horizontal = event.hasPreciseScrollingDeltas
            ? event.scrollingDeltaX
            : CGFloat(event.deltaX) * 8

        // Prefer vertical delta mapped to horizontal; fall back to native horizontal.
        let delta: CGFloat
        if abs(vertical) >= abs(horizontal), abs(vertical) > 0.01 {
            delta = -vertical
        } else if abs(horizontal) > 0.01 {
            delta = horizontal
        } else {
            return false
        }

        let clipView = scrollView.contentView
        var origin = clipView.bounds.origin
        origin.x += delta
        let maxX = max(0, document.frame.width - clipView.bounds.width)
        origin.x = min(max(origin.x, 0), maxX)
        clipView.scroll(to: origin)
        scrollView.reflectScrolledClipView(clipView)
        return true
    }

    private func isTextInput(_ view: NSView) -> Bool {
        var current: NSView? = view
        while let v = current {
            if v is NSTextView || v is NSTextField { return true }
            current = v.superview
        }
        return false
    }

    // MARK: - Clip drag (intercept before ScrollView)

    private func setupDragMouseMonitor() {
        tearDownDragMouseMonitor()
        dragMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            guard let self, self.isShowing, event.window === self, let contentView else { return event }

            let local = contentView.convert(event.locationInWindow, from: nil)
            guard let hit = contentView.hitTest(local), !self.isTextInput(hit) else { return event }
            guard let bridge = ClipCardMouseBridge.bridge(in: hit) else { return event }

            bridge.handleMouseDown(event)
            return nil
        }
    }

    private func tearDownDragMouseMonitor() {
        if let m = dragMouseMonitor { NSEvent.removeMonitor(m); dragMouseMonitor = nil }
    }

    override var canBecomeKey: Bool  { true  }
    override var canBecomeMain: Bool { false }
}
