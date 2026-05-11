import SwiftUI
import UniformTypeIdentifiers

struct NotchTrayView: View {
    @Environment(NotchTrayViewModel.self) private var vm
    @State private var isHoveringPill  = false
    @State private var isHoveringPanel = false
    @State private var isDropTargeted  = false
    @State private var expanded        = false   // local state — driven by withAnimation
    @State private var showContent     = false   // stagger inner content after shape opens

    private var menuBarHeight: CGFloat {
        guard let s = NSScreen.main else { return 24 }
        return s.frame.maxY - s.visibleFrame.maxY
    }

    var body: some View {
        VStack(spacing: 0) {
            pillRow.frame(height: menuBarHeight)
            if expanded {
                expandedPanel
                    .transition(
                        .asymmetric(
                            insertion: .opacity.animation(
                                .spring(response: 0.34, dampingFraction: 0.82)),
                            removal: .opacity.animation(.easeIn(duration: 0.12))
                        )
                    )
            }
        }
        // Shell background is sized to the VStack — grows with content, not with window frame
        .background { morphingShell }
        .frame(maxWidth: .infinity, alignment: .top)
        // Entry / exit — identical spring to the launcher
        .scaleEffect(vm.isVisible ? 1.0 : 0.88, anchor: .top)
        .opacity(vm.isVisible ? 1.0 : 0)
        .animation(.spring(response: 0.28, dampingFraction: 0.80), value: vm.isVisible)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .environment(\.colorScheme, .dark)
        .onChange(of: vm.state) { _, state in
            // Single withAnimation drives: panel appear/disappear, VStack height, shell corner radius
            withAnimation(.spring(response: 0.36, dampingFraction: 0.82)) {
                expanded = (state == .expanded)
            }
            if state == .expanded {
                Task {
                    try? await Task.sleep(for: .milliseconds(60))
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.84)) {
                        showContent = true
                    }
                }
            } else {
                withAnimation(.easeIn(duration: 0.12)) { showContent = false }
            }
        }
    }

    // MARK: - Background shell — sized to VStack content, not the window

    private var morphingShell: some View {
        let cr: CGFloat    = expanded ? 22 : 28
        let glowing        = vm.isDropHighlighted || isDropTargeted
        return RoundedRectangle(cornerRadius: cr, style: .continuous)
            .fill(Color(red: 0.08, green: 0.08, blue: 0.10).opacity(0.97))
            .overlay {
                RoundedRectangle(cornerRadius: cr, style: .continuous)
                    .stroke(
                        glowing ? Color.blue.opacity(0.60) : Color.white.opacity(0.16),
                        lineWidth: 1
                    )
            }
            // Light, spread shadow — close layer + far layer, no heavy bleed around corners
            .shadow(color: .black.opacity(0.55), radius: 18, x: 0, y:  6)
            .shadow(color: .black.opacity(0.28), radius: 48, x: 0, y: 18)
            .shadow(color: .black.opacity(0.12), radius: 90, x: 0, y: 38)
            .animation(.spring(response: 0.36, dampingFraction: 0.82), value: expanded)
            .animation(.easeInOut(duration: 0.18), value: glowing)
    }

    // MARK: - Compact pill row

    private var pillRow: some View {
        HStack(spacing: 10) {
            if vm.files.isEmpty {
                compactIdleContent
            } else {
                compactFilledContent
            }
        }
        .padding(.horizontal, 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onHover { h in
            isHoveringPill = h
            if h { vm.expand() }
            else {
                Task {
                    try? await Task.sleep(for: .milliseconds(300))
                    if !isHoveringPill && !isHoveringPanel { vm.collapse() }
                }
            }
        }
    }

    private var compactIdleContent: some View {
        HStack(spacing: 6) {
            Image(systemName: "tray")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.40))
            Text("Echo Tray")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.35))
        }
    }

    private var compactFilledContent: some View {
        HStack(spacing: 9) {
            let shown = Array(vm.files.prefix(3))
            ZStack(alignment: .leading) {
                ForEach(Array(shown.reversed().enumerated()), id: \.element.id) { i, file in
                    Image(nsImage: file.icon)
                        .resizable().interpolation(.high)
                        .frame(width: 18, height: 18)
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                        .shadow(color: .black.opacity(0.5), radius: 3, y: 1)
                        .offset(x: CGFloat(shown.count - 1 - i) * 9)
                }
            }
            .frame(width: CGFloat(min(shown.count, 3) - 1) * 9 + 18, height: 18)

            Text("\(vm.files.count)")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .contentTransition(.numericText())
        }
        .animation(.spring(response: 0.28, dampingFraction: 0.78), value: vm.files.count)
    }

    // MARK: - Expanded panel

    private var expandedPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                modeButton(title: "Copy", icon: "doc.on.doc", mode: .copy)
                modeButton(title: "Move", icon: "arrow.forward", mode: .move)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 12)
            .opacity(showContent ? 1 : 0)
            .offset(y: showContent ? 0 : -5)
            .animation(.spring(response: 0.28, dampingFraction: 0.82).delay(0.02), value: showContent)

            Rectangle()
                .fill(Color.white.opacity(0.07))
                .frame(height: 0.5)
                .padding(.horizontal, 16)
                .opacity(showContent ? 1 : 0)

            if vm.files.isEmpty {
                dropZone
                    .padding(.horizontal, 14)
                    .padding(.top, 12)
                    .padding(.bottom, 14)
                    .opacity(showContent ? 1 : 0)
                    .offset(y: showContent ? 0 : 6)
                    .animation(.spring(response: 0.30, dampingFraction: 0.82).delay(0.06), value: showContent)
            } else {
                fileCardRow
                    .padding(.bottom, 12)
                    .opacity(showContent ? 1 : 0)
                    .offset(y: showContent ? 0 : 6)
                    .animation(.spring(response: 0.30, dampingFraction: 0.82).delay(0.06), value: showContent)
            }
        }
        .onHover { h in
            isHoveringPanel = h
            if !h {
                Task {
                    try? await Task.sleep(for: .milliseconds(300))
                    if !isHoveringPanel && !isHoveringPill { vm.collapse() }
                }
            }
        }
    }

    // MARK: - Copy / Move mode button

    private func modeButton(title: String, icon: String,
                            mode: NotchTrayViewModel.TransferMode) -> some View {
        let selected = vm.transferMode == mode
        return Button {
            withAnimation(.spring(response: 0.26, dampingFraction: 0.76)) {
                vm.transferMode = mode
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(selected ? Color.white : Color.white.opacity(0.45))
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background {
                Capsule()
                    .fill(selected
                          ? Color(red: 0.98, green: 0.58, blue: 0.11)
                          : Color.white.opacity(0.09))
            }
            .overlay {
                Capsule()
                    .stroke(selected ? Color.clear : Color.white.opacity(0.12), lineWidth: 0.5)
            }
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.24, dampingFraction: 0.76), value: selected)
    }

    // MARK: - Dashed drop zone

    private var dropZone: some View {
        let glowing = vm.isDropHighlighted || isDropTargeted
        return ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(glowing ? 0.05 : 0.03))
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(style: StrokeStyle(lineWidth: 1.5, dash: [8, 5]))
                .foregroundStyle(glowing ? Color.blue.opacity(0.70) : Color.white.opacity(0.18))
            VStack(spacing: 10) {
                Image(systemName: "arrow.down.doc.fill")
                    .font(.system(size: 30, weight: .light))
                    .foregroundStyle(.white.opacity(glowing ? 0.90 : 0.45))
                    .symbolEffect(.bounce, value: glowing)
                Text("Drop files here")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
                Text(vm.transferMode == .move
                     ? "Mode: Move — original will be deleted"
                     : "Mode: Copy — original stays untouched")
                    .font(.system(size: 11))
                    .foregroundStyle(
                        vm.transferMode == .move
                            ? Color(red: 0.98, green: 0.58, blue: 0.11).opacity(0.90)
                            : Color.white.opacity(0.32)
                    )
            }
            .padding(.vertical, 28)
        }
        .frame(maxWidth: .infinity)
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted, perform: handleDrop)
        .onChange(of: isDropTargeted) { _, t in vm.setDropTargetActive(t) }
        .animation(.easeInOut(duration: 0.18), value: glowing)
    }

    // MARK: - Horizontal file cards

    private var fileCardRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: NotchTrayWindow.cardSpacing) {
                ForEach(vm.files) { file in fileCard(file) }
                dropMoreTarget
            }
            .padding(.horizontal, NotchTrayWindow.listHPad)
            .padding(.vertical, 10)
        }
        .frame(height: NotchTrayWindow.listAreaHeight - 8)
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted, perform: handleDrop)
    }

    private var dropMoreTarget: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.04))
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(style: StrokeStyle(lineWidth: 1.2, dash: [5, 4]))
                .foregroundStyle(Color.white.opacity(0.15))
            Image(systemName: "plus")
                .font(.system(size: 18, weight: .light))
                .foregroundStyle(.white.opacity(0.28))
        }
        .frame(width: NotchTrayWindow.cardWidth, height: 78)
    }

    private func fileCard(_ file: TrayFile) -> some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 6) {
                Image(nsImage: file.icon)
                    .resizable().interpolation(.high)
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .shadow(color: .black.opacity(0.50), radius: 6, y: 2)
                Text(file.name)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.white.opacity(0.70))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(width: NotchTrayWindow.cardWidth - 10)
            }
            .frame(width: NotchTrayWindow.cardWidth)
            .padding(.top, 4)

            Button {
                withAnimation(.spring(response: 0.22, dampingFraction: 0.78)) {
                    vm.remove(id: file.id)
                }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(.white.opacity(0.55))
                    .background(Circle().fill(Color.black.opacity(0.40)).padding(3))
            }
            .buttonStyle(.plain)
            .offset(x: 5, y: -2)
        }
        .contentShape(Rectangle())
        .onDrag { NSItemProvider(contentsOf: file.url) ?? NSItemProvider() }
    }

    // MARK: - Drop handler

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        let typeID    = UTType.fileURL.identifier
        let viewModel = vm
        for provider in providers {
            guard provider.hasItemConformingToTypeIdentifier(typeID) else { continue }
            provider.loadItem(forTypeIdentifier: typeID, options: nil) { item, _ in
                let url: URL?
                if let u = item as? URL          { url = u }
                else if let d = item as? Data    { url = URL(dataRepresentation: d, relativeTo: nil) }
                else                             { url = nil }
                guard let url else { return }
                DispatchQueue.main.async { viewModel.addFiles([url]) }
            }
        }
        return true
    }
}
