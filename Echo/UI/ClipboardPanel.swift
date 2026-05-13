import AppKit
import SwiftUI

/// A non-activating floating NSPanel that slides up from the bottom of the screen.
/// "Non-activating" means the previously focused app (e.g. VS Code) remains key,
/// enabling seamless drag-and-drop out of the panel.
final class ClipboardPanel: NSPanel {
    private(set) var isShowing = false

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

    func show() {
        guard !isShowing, let screen = NSScreen.main else { return }
        let vis = screen.visibleFrame
        let (x, w, h) = (vis.minX + 20, vis.width - 40, CGFloat(270))

        // Start off-screen below the dock, then spring up
        setFrame(NSRect(x: x, y: vis.minY - h - 10, width: w, height: h), display: false)
        isShowing = true
        // Activate Echo so the search field can receive keyboard input.
        NSApp.activate(ignoringOtherApps: true)
        makeKeyAndOrderFront(nil)

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.55
            // Cubic-bezier approximating a spring with slight overshoot
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.34, 1.56, 0.64, 1.0)
            animator().setFrame(NSRect(x: x, y: vis.minY + 10, width: w, height: h), display: true)
        }
    }

    func hide() {
        guard isShowing else { return }
        let f = frame
        isShowing = false

        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.28
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            animator().setFrame(
                NSRect(x: f.minX, y: f.minY - f.height - 20, width: f.width, height: f.height),
                display: true
            )
        }, completionHandler: {
            // The completion block runs on the main thread; assert isolation so Swift 6 allows
            // calling @MainActor methods without an async hop.
            MainActor.assumeIsolated { self.orderOut(nil) }
        })
    }

    func toggle() { isShowing ? hide() : show() }

    override var canBecomeKey: Bool  { true  }
    override var canBecomeMain: Bool { false }
}
