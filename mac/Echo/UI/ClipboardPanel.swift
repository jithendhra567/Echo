import AppKit
import SwiftUI

/// A non-activating floating NSPanel that slides up from the bottom of the screen.
/// "Non-activating" means the previously focused app (e.g. VS Code) remains key,
/// enabling seamless drag-and-drop out of the panel.
final class ClipboardPanel: NSPanel {
    private(set) var isShowing = false
    private var localKeyMonitor: Any?

    init(viewModel: ClipViewModel) {
        super.init(
            contentRect: .zero,
            styleMask: [.nonactivatingPanel, .fullSizeContentView, .borderless],
            backing: .buffered,
            defer: false
        )
        configure()
        contentView = NSHostingView(
            rootView: ClipDashboardView().environment(viewModel)
        )
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

    // MARK: - Show / Hide

    /// Smooth deceleration — no overshoot, feels like rising from below the dock.
    private static let slideUpTiming = CAMediaTimingFunction(controlPoints: 0.22, 1.0, 0.36, 1.0)
    private static let slideDownTiming = CAMediaTimingFunction(controlPoints: 0.55, 0.0, 0.75, 0.4)

    private func layoutFrames(for screen: NSScreen) -> (start: NSRect, final: NSRect) {
        let vis = screen.visibleFrame
        let w = vis.width - 40
        let h: CGFloat = 270
        let x = vis.minX + 20
        let final = NSRect(x: x, y: vis.minY + 12, width: w, height: h)
        // Start fully below the visible frame so the panel clearly emerges from off-screen.
        let start = NSRect(x: x, y: vis.minY - h - 36, width: w, height: h)
        return (start, final)
    }

    func show() {
        guard !isShowing, let screen = NSScreen.main else { return }
        let frames = layoutFrames(for: screen)

        alphaValue = 0
        setFrame(frames.start, display: false)
        isShowing = true
        makeKeyAndOrderFront(nil)
        setupKeyMonitor()

        // Wait one turn so the window is composited at the off-screen pose before animating.
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isShowing else { return }
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.50
                ctx.timingFunction = Self.slideUpTiming
                ctx.allowsImplicitAnimation = true
                self.animator().alphaValue = 1
                self.animator().setFrame(frames.final, display: true)
            }
        }
    }

    func hide() {
        guard isShowing, let screen = NSScreen.main else { return }
        let f = frame
        let vis = screen.visibleFrame
        isShowing = false
        tearDownKeyMonitor()

        let exitFrame = NSRect(x: f.minX, y: vis.minY - f.height - 36, width: f.width, height: f.height)

        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.36
            ctx.timingFunction = Self.slideDownTiming
            ctx.allowsImplicitAnimation = true
            self.animator().alphaValue = 0
            self.animator().setFrame(exitFrame, display: true)
        }, completionHandler: {
            MainActor.assumeIsolated {
                self.alphaValue = 1
                self.orderOut(nil)
            }
        })
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

    override var canBecomeKey: Bool  { true  }
    override var canBecomeMain: Bool { false }
}
