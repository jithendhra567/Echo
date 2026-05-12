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
    @State private var isDropTargeted = false
    @State private var closeTask: Task<Void, Never>?
    @State private var openHoverTask: Task<Void, Never>?

    private static let openHoverDebounce: Duration = .milliseconds(200)

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
            // Click-through canvas. SwiftUI hit-test returns nil for these
            // points, so the menu bar / app behind us stay reachable.
            Color.clear.allowsHitTesting(false)

            pill(module: module, moduleHot: moduleHot)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .environment(\.colorScheme, .dark)
        .onChange(of: isDropTargeted) { _, t in module.setDropTargeted(t) }
        .onDrop(of: dropTypes, isTargeted: $isDropTargeted) { providers in
            routeDrop(providers: providers, module: module)
        }
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
                    .padding(.horizontal, NotchSizing.Corners.openBottom)
                    .padding(.bottom, 6)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(width: width, height: height, alignment: .top)
        .background(Color.black)
        .clipShape(shape)
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
        VStack(spacing: 0) {
            module.openView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            if vm.modules.count > 1 {
                tabStrip(active: module)
            }
        }
        .transition(.opacity)
    }

    @ViewBuilder
    private func tabStrip(active: any NotchModule) -> some View {
        HStack(spacing: 14) {
            ForEach(vm.modules, id: \.id) { m in
                let isActive = m.id == active.id
                Button {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                        vm.selectModule(id: m.id)
                    }
                } label: {
                    Image(systemName: m.iconName)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.white.opacity(isActive ? 0.95 : 0.35))
                        .frame(width: 18, height: 14)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .frame(height: 14)
        .padding(.bottom, 2)
    }

    // MARK: - Sizing

    private var edgePadding: CGFloat { isOpen ? 22 : 12 }

    /// Pill dimensions are *explicit* on the outer VStack rather than per
    /// child, so SwiftUI animates a single `frame` change instead of trying
    /// to keep two layers in sync.
    private func pillWidth(module: any NotchModule, moduleHot: Bool) -> CGFloat {
        if isOpen { return NotchSizing.openSize.width }
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
                try? await Task.sleep(for: Self.openHoverDebounce)
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
        // lost just because Music is the focused tab.
        if vm.tray.handleDrop(providers: providers) {
            vm.selectModule(id: vm.tray.id)
            return true
        }
        return module.handleDrop(providers: providers)
    }
}
