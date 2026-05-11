import AppKit
import SwiftUI

final class NotchTrayWindow: NSPanel {

    let viewModel           = NotchTrayViewModel()
    private let dragWatcher = GlobalDragMonitor()

    static let compactWidth:   CGFloat = 200
    static let expandedWidth:  CGFloat = 480
    static let expandedExtraH: CGFloat = 220
    static let cardWidth:      CGFloat = 78
    static let cardSpacing:    CGFloat = 10
    static let listHPad:       CGFloat = 18
    static let listAreaHeight: CGFloat = 120

    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.nonactivatingPanel, .fullSizeContentView, .borderless],
            backing: .buffered,
            defer:   false
        )
        configure()
        let hv = PanelHostingView(rootView: NotchTrayView().environment(viewModel))
        hv.sizingOptions = []
        contentView = hv
        setFrame(targetFrame(), display: false)
        startObservingViewModel()
        startDragMonitor()
    }

    private func configure() {
        isFloatingPanel   = true
        level             = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 2)
        backgroundColor   = .clear
        isOpaque          = false
        hasShadow         = false
        isMovableByWindowBackground = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        ignoresMouseEvents = true
        appearance = NSAppearance(named: .darkAqua)
    }

    // MARK: - Frame

    private func targetFrame() -> NSRect {
        guard let screen = NSScreen.main else {
            return NSRect(x: 0, y: 0, width: Self.compactWidth, height: 24)
        }
        let mbH   = NotchPositionHelper.menuBarHeight(for: screen)
        let cx    = NotchPositionHelper.trayCenterX(for: screen)
        let baseY = NotchPositionHelper.menuBarBaseY(for: screen)

        let (width, extraH): (CGFloat, CGFloat)

        switch viewModel.state {
        case .hidden, .compact:
            width = Self.compactWidth;   extraH = 0
        case .expanded:
            if viewModel.files.isEmpty {
                width = Self.expandedWidth; extraH = Self.expandedExtraH
            } else {
                let n   = CGFloat(viewModel.files.count)
                let nat = n * (Self.cardWidth + Self.cardSpacing) + Self.listHPad * 2
                width   = min(max(Self.expandedWidth, nat), screen.frame.width - 80)
                extraH  = Self.listAreaHeight
            }
        }

        return NSRect(x: cx - width / 2, y: baseY - extraH,
                      width: width, height: mbH + extraH)
    }

    // MARK: - Observation loop

    private func startObservingViewModel() { observeNext() }

    private func observeNext() {
        withObservationTracking {
            _ = viewModel.state
            _ = viewModel.files.count
        } onChange: {
            Task { @MainActor [weak self] in
                self?.applyStateChange()
                self?.observeNext()
            }
        }
    }

    private func applyStateChange() {
        switch viewModel.state {
        case .hidden:
            // SwiftUI already set isVisible = false → animates out
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(310))
                guard self.viewModel.state == .hidden else { return }
                self.ignoresMouseEvents = true
                self.orderOut(nil)
            }

        case .compact:
            if !isVisible {
                // First appearance — window invisible at NSWindow level while SwiftUI renders
                setFrame(targetFrame(), display: false)
                alphaValue = 0
                ignoresMouseEvents = false
                orderFrontRegardless()
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(20))
                    self.alphaValue = 1
                    self.viewModel.isVisible = true
                }
            } else {
                // Collapsing from expanded — let SwiftUI animate first, THEN shrink frame
                // so the collapse animation isn't clipped by a premature resize.
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(380))
                    guard self.viewModel.state == .compact else { return }
                    self.setFrame(self.targetFrame(), display: false)
                }
            }

        case .expanded:
            if !isVisible {
                // Direct appearance in expanded state
                setFrame(targetFrame(), display: false)
                alphaValue = 0
                ignoresMouseEvents = false
                orderFrontRegardless()
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(20))
                    self.alphaValue = 1
                    self.viewModel.isVisible = true
                }
            } else {
                // Expanding from compact — grow frame INSTANTLY so SwiftUI has
                // full space to animate into. No NSAnimationContext here.
                setFrame(targetFrame(), display: false)
            }
        }
    }

    // MARK: - Drag monitor

    private func startDragMonitor() {
        dragWatcher.onDragBegan = { [weak self] in
            self?.viewModel.globalDragBegan()
        }
        dragWatcher.onDragMoved = { [weak self] point in
            guard let self else { return }
            let halo = self.frame.insetBy(dx: -80, dy: -40)
            if halo.contains(point), self.viewModel.state == .compact {
                self.viewModel.setDropTargetActive(true)
            } else if !halo.insetBy(dx: -20, dy: -20).contains(point),
                      self.viewModel.state == .expanded,
                      self.viewModel.files.isEmpty {
                self.viewModel.setDropTargetActive(false)
            }
        }
        dragWatcher.onDragEnded = { [weak self] in
            self?.viewModel.globalDragEnded()
        }
        dragWatcher.start()
    }

    override var canBecomeKey:  Bool { false }
    override var canBecomeMain: Bool { false }
}

// MARK: - Crash-proof hosting view

/// NSHostingView's `updateConstraints` runs `updateWindowContentSizeExtremaIfNecessary`,
/// which performs a SwiftUI layout pass. During that pass, `scaleEffect` / `opacity`
/// animations call `invalidateTransform` → `requestUpdate` → `setNeedsUpdateConstraints`,
/// re-entering the same constraint cycle. AppKit throws after N passes, crashing.
///
/// The guard below makes `setNeedsUpdateConstraints` a no-op while a constraint pass
/// is already in flight, breaking the loop without skipping any real work.
private final class PanelHostingView<Content: View>: NSHostingView<Content> {
    private var inConstraintPass        = false
    private var constraintUpdatePending = false
    private var layoutUpdatePending     = false

    override var intrinsicContentSize: CGSize { .zero }

    // ── Unified guard against all three crash paths ──────────────────────────
    //
    // Path A: updateConstraints → updateWindowContentSizeExtremaIfNecessary
    //         → SwiftUI body eval → invalidateTransform → requestUpdate
    //         → needsUpdateConstraints = true  (caught by inConstraintPass)
    //
    // Path B: windowDidLayout → updateAnimatedWindowSize → _setFrameCommon
    //         → setFrameSize → KVO "frameSize" → invalidateSafeAreaCornerInsets
    //         → requestUpdate → needsUpdateConstraints = true  (many per cycle)
    //
    // Path C: windowDidLayout → updateAnimatedWindowSize → _setFrameCommon
    //         → setFrameSize → KVO "frameSize" → invalidateSafeAreaInsets
    //         → requestUpdate → setNeedsLayout: → _postWindowNeedsLayout → crash
    //
    // All three call into these setters. We forward at most one `true` per
    // run-loop tick (pending flags reset after current sources drain) and we
    // never forward while a constraint pass is in flight.
    override var needsUpdateConstraints: Bool {
        get { super.needsUpdateConstraints }
        set {
            guard !inConstraintPass else { return }
            if newValue {
                guard !constraintUpdatePending else { return }
                constraintUpdatePending = true
                super.needsUpdateConstraints = true
                DispatchQueue.main.async { [weak self] in
                    self?.constraintUpdatePending = false
                }
            } else {
                constraintUpdatePending = false
                super.needsUpdateConstraints = false
            }
        }
    }

    override var needsLayout: Bool {
        get { super.needsLayout }
        set {
            if newValue {
                guard !layoutUpdatePending else { return }
                layoutUpdatePending = true
                super.needsLayout = true
                DispatchQueue.main.async { [weak self] in
                    self?.layoutUpdatePending = false
                }
            } else {
                layoutUpdatePending = false
                super.needsLayout = false
            }
        }
    }

    override func updateConstraints() {
        inConstraintPass = true
        super.updateConstraints()
        inConstraintPass = false
    }
}
