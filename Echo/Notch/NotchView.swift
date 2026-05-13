import SwiftUI
import UniformTypeIdentifiers

/// SwiftUI root inside `NotchPanel`. Renders the pill centered at the top of
/// the panel.
///
/// Design rules (mirrors boring.notch's ContentView):
///
/// - **One** `.animation(activeSpring, value: notchState)` modifier on the
///   pill chrome. State changes go through `withAnimation` in `handleHover`
///   so SwiftUI never has to fight a pile of competing modifiers.
/// - The pill's hit area is a plain `Rectangle` `contentShape`, not the
///   animated `NotchShape`. Hover hit-tests are then one rect contains check
///   per mouse move instead of a path traversal.
/// - No `compositingGroup()` — at this size it just adds a GPU layer to
///   rebuild every animation frame.
/// - **Open** waits 0.25s while the cursor stays on the pill so accidental
///   menu-bar passes do not expand the notch. Close keeps a short debounce
///   so quick cursor slips off the edge do not collapse.
struct NotchView: View {
    @Environment(NotchViewModel.self) private var vm
    @Environment(NotchLayoutGuide.self) private var notchLayout
    @State private var isDropTargeted = false
    @State private var closeTask: Task<Void, Never>?
    @State private var openHoverTask: Task<Void, Never>?

    /// Debounce when a module has content to surface (tray files).
    private static let openHoverDebounceActive: Duration  = .milliseconds(200)
    /// Longer debounce when idle so cursor passes near the notch to reach app
    /// windows below (e.g. Chrome tabs) do not accidentally expand the pill.
    private static let openHoverDebounceIdle:   Duration  = .milliseconds(500)

    private var openSpring: Animation {
        let s = NotchSizing.Spring.open
        return .spring(response: s.response, dampingFraction: s.damping, blendDuration: s.blend)
    }
    private var closeSpring: Animation {
        let s = NotchSizing.Spring.close
        return .spring(response: s.response, dampingFraction: s.damping, blendDuration: s.blend)
    }
    private var activeSpring: Animation {
        vm.notchState == .open ? openSpring : closeSpring
    }

    private var isOpen: Bool { vm.notchState == .open }

    private var topRadius:    CGFloat { isOpen ? NotchSizing.Corners.openTop    : NotchSizing.Corners.closedTop }
    private var bottomRadius: CGFloat { isOpen ? NotchSizing.Corners.openBottom : NotchSizing.Corners.closedBottom }

    var body: some View {
        let module     = vm.activeModule
        let moduleHot  = module.isActive          // cache so body doesn't re-read inside child computations
        let dropTypes: [UTType] = [.fileURL, .url]

        ZStack(alignment: .top) {
            // Background fills the window so the ZStack has a defined size;
            // hit-testing is handled at the NSHostingView level (PillHostingView).
            Color.clear.allowsHitTesting(false)

            pill(module: module, moduleHot: moduleHot)
                .onChange(of: isDropTargeted) { _, t in module.setDropTargeted(t) }
                .onDrop(of: dropTypes, isTargeted: $isDropTargeted) { providers in
                    routeDrop(providers: providers, module: module)
                }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .environment(\.colorScheme, .dark)
        .onAppear { syncEchoChromeTopInset() }
        .onChange(of: vm.notchState) { _, _ in syncEchoChromeTopInset() }
    }

    private func syncEchoChromeTopInset() {
        notchLayout.setTopInset(vm.notchState == .open ? NotchSizing.expandedPillHeight : 0)
    }

    // MARK: - The pill

    @ViewBuilder
    private func pill(module: any NotchModule, moduleHot: Bool) -> some View {
        let width        = pillWidth(module: module, moduleHot: moduleHot)
        let height       = pillHeight()
        let headerHeight = headerHeight(module: module)
        let sumR         = topRadius + bottomRadius
        let radiusScale  = sumR > 0 ? min(1, (height - 1) / (sumR + 2)) : 1
        let effTopR      = topRadius * radiusScale
        let effBottomR   = bottomRadius * radiusScale
        let shape        = NotchShape(topCornerRadius: effTopR, bottomCornerRadius: effBottomR)

        VStack(spacing: 0) {
            closedBar(module: module, moduleHot: moduleHot)
                .frame(height: headerHeight)
                .clipped()                  // hide the bar instead of removing it structurally — smoother spring

            if isOpen {
                openContent(module: module)
                    .padding(.bottom, 2)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(width: width, height: height, alignment: .top)
        .background(Color.black)
        .compositingGroup()
        .clipShape(shape)
        .shadow(color: .black.opacity(isOpen ? 0.16 : 0), radius: isOpen ? 26 : 0, x: 0, y: isOpen ? 12 : 0)
        .shadow(color: .black.opacity(isOpen ? 0.048 : 0), radius: isOpen ? 118 : 0, x: 0, y: isOpen ? 40 : 0)
        .contentShape(Rectangle())          // ← cheap rect hit-test for hover
        .animation(activeSpring, value: vm.notchState)
        .animation(activeSpring, value: width)
        .animation(activeSpring, value: headerHeight)
        .onHover { handleHover($0) }
    }

    /// Height of the closed-bar header strip inside the pill.
    /// - Closed state: always the physical notch height (the closed bar *is* the pill).
    /// - Open state: depends on the module — it's hidden (`0`) when the module's
    ///   open view already surfaces the same info (e.g. clock).
    private func headerHeight(module: any NotchModule) -> CGFloat {
        guard isOpen else { return vm.closedNotchSize.height }
        return module.showsClosedHeaderInOpen ? vm.closedNotchSize.height : 0
    }

    /// The closed-state bar always renders (it stays visible inside the open
    /// pill as the "header"). When the active module is idle it goes fully
    /// transparent — there's nothing useful to surface.
    @ViewBuilder
    private func closedBar(module: any NotchModule, moduleHot: Bool) -> some View {
        HStack(spacing: 0) {
            module.closedLeft
                .frame(minWidth: 22, alignment: .center)
                .padding(.leading, edgePadding)

            Spacer(minLength: 6)
            module.closedCenter
            Spacer(minLength: 6)

            module.closedRight
                .frame(minWidth: 22, alignment: .center)
                .padding(.trailing, edgePadding)
        }
        .opacity(moduleHot || isOpen ? 1 : 0)
        .animation(.easeInOut(duration: 0.14), value: moduleHot)
    }

    @ViewBuilder
    private func openContent(module: any NotchModule) -> some View {
        module.openView
            .padding(.top, NotchSizing.openContentTopInset)
            .padding(.horizontal, NotchSizing.openContentHorizontalInset)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .transition(.opacity)
    }

    // MARK: - Sizing

    private var edgePadding: CGFloat { isOpen ? 22 : 12 }

    /// Pill dimensions are *explicit* on the outer VStack rather than per
    /// child, so SwiftUI animates a single `frame` change instead of trying
    /// to keep two layers in sync.
    private func pillWidth(module: any NotchModule, moduleHot: Bool) -> CGFloat {
        if isOpen { return module.openExpandedWidth }
        if moduleHot { return vm.closedNotchSize.width + module.closedExtraWidth }
        return vm.closedNotchSize.width
    }

    private func pillHeight() -> CGFloat {
        isOpen ? NotchSizing.openSize.height : vm.closedNotchSize.height
    }

    // MARK: - Hover

    private func handleHover(_ hovering: Bool) {
        if hovering {
            closeTask?.cancel()
            closeTask = nil
            openHoverTask?.cancel()
            openHoverTask = Task {
                let delay = vm.anyModuleActive
                    ? Self.openHoverDebounceActive
                    : Self.openHoverDebounceIdle
                try? await Task.sleep(for: delay)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    withAnimation(openSpring) {
                        vm.isHovering = true
                        vm.open()
                    }
                }
            }
            return
        }

        openHoverTask?.cancel()
        openHoverTask = nil
        closeTask?.cancel()

        // Tiny tolerance for quick cursor slips off the pill edge.
        closeTask = Task {
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation(closeSpring) {
                    vm.isHovering = false
                    if !vm.anyModuleActive {
                        vm.close()
                    } else {
                        // Keep peek-state but mark non-hover.
                        vm.close()
                    }
                }
            }
        }
    }

    // MARK: - Drop routing

    private func routeDrop(providers: [NSItemProvider], module: any NotchModule) -> Bool {
        // Drops always go to the tray — drag dropping a file shouldn't be
        // lost just because another module tab is focused.
        if vm.tray.handleDrop(providers: providers) {
            return true
        }
        return module.handleDrop(providers: providers)
    }
}
