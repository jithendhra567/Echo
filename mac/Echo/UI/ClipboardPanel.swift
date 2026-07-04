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
    private var isOpening = false
    private var localKeyMonitor: Any?
    private var hideTask: DispatchWorkItem?
    private var showTask: Task<Void, Never>?
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
        guard !isShowing, !isOpening, let screen = NSScreen.main else { return }
        hideTask?.cancel()
        hideTask = nil
        showTask?.cancel()

        isOpening = true
        showTask = Task { @MainActor in
            await viewModel.refreshClips()
            guard !Task.isCancelled else {
                isOpening = false
                return
            }

            presentation.isPresented = false
            setFrame(windowFrame(for: screen), display: true)
            isOpening = false
            isShowing = true
            orderFrontRegardless()
            makeKey()
            setupKeyMonitor()

            DispatchQueue.main.async { [weak self] in
                guard let self, self.isShowing else { return }
                self.presentation.isPresented = true
            }
        }
    }

    func hide() {
        showTask?.cancel()
        showTask = nil
        isOpening = false
        guard isShowing else { return }
        hideTask?.cancel()

        isShowing = false
        tearDownKeyMonitor()
        presentation.isPresented = false

        let work = DispatchWorkItem { [weak self] in
            guard let self, !self.isShowing else { return }
            self.orderOut(nil)
        }
        hideTask = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.32, execute: work)
    }

    func toggle() {
        if isShowing || isOpening { hide() } else { show() }
    }

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
