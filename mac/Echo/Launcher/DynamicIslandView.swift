import SwiftUI
import AppKit

// MARK: - Dimension constants (shared with DynamicIslandWindow for hit-test math)

extension DynamicIslandView {
    static let pillWidth:      CGFloat = 120
    static let pillHeight:     CGFloat = 34
    static let expandedWidth:  CGFloat = 720
    static let expandedHeight: CGFloat = 440
}

// MARK: - Main view

struct DynamicIslandView: View {
    @Environment(LauncherViewModel.self) private var vm
    @Environment(ClipViewModel.self)     private var clipVM
    @FocusState private var isSearchFocused: Bool

    @State private var showContent    = false
    @State private var showTimestamps = false

    private var iw: CGFloat { vm.isExpanded ? Self.expandedWidth  : Self.pillWidth  }
    private var ih: CGFloat { vm.isExpanded ? Self.expandedHeight : Self.pillHeight }
    private var cr: CGFloat { vm.isExpanded ? 24 : 17 }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                islandBackground
                if showContent { expandedContent.transition(.opacity) }
            }
            .environment(\.colorScheme, .dark)
            .frame(width: iw, height: ih)
            .animation(
                vm.isExpanded
                    ? .spring(response: 0.34, dampingFraction: 0.78)
                    : .spring(response: 0.24, dampingFraction: 0.88),
                value: vm.isExpanded
            )
            .scaleEffect(vm.isVisible ? 1.0 : 0.85, anchor: .top)
            .opacity(vm.isVisible ? 1.0 : 0)
            .animation(.spring(response: 0.22, dampingFraction: 0.82), value: vm.isVisible)
            .frame(width: DynamicIslandWindow.windowSize.width)

            Spacer().allowsHitTesting(false)
        }
        .frame(
            width:  DynamicIslandWindow.windowSize.width,
            height: DynamicIslandWindow.windowSize.height,
            alignment: .top
        )
        .onChange(of: vm.isExpanded) { _, expanded in
            if expanded {
                vm.expand()
                Task {
                    try? await Task.sleep(for: .milliseconds(50))
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.84)) {
                        showContent = true
                    }
                    isSearchFocused = true
                    try? await Task.sleep(for: .milliseconds(350))
                    withAnimation(.easeIn(duration: 0.25)) { showTimestamps = true }
                }
            } else {
                withAnimation(.easeIn(duration: 0.10)) { showContent = false }
                isSearchFocused = false
                showTimestamps = false
            }
        }
    }

    // MARK: - Background

    private var islandBackground: some View {
        RoundedRectangle(cornerRadius: cr, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay {
                RoundedRectangle(cornerRadius: cr, style: .continuous)
                    .fill(Color.black.opacity(0.72))
            }
            .overlay {
                RoundedRectangle(cornerRadius: cr, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [.white.opacity(0.18), .white.opacity(0.06)],
                            startPoint: .top, endPoint: .bottom
                        ),
                        lineWidth: 0.6
                    )
            }
            .shadow(color: .black.opacity(0.28), radius: 18, y: 6)
            .shadow(color: .black.opacity(0.10), radius: 80, y: 32)
            .animation(
                vm.isExpanded
                    ? .spring(response: 0.34, dampingFraction: 0.78)
                    : .spring(response: 0.24, dampingFraction: 0.88),
                value: vm.isExpanded
            )
    }

    // MARK: - Expanded content

    private var expandedContent: some View {
        VStack(spacing: 0) {
            searchField
            Rectangle()
                .fill(Color.white.opacity(0.07))
                .frame(height: 1)
                .padding(.horizontal, 10)
            HStack(spacing: 0) {
                appColumn
                Rectangle()
                    .fill(Color.white.opacity(0.07))
                    .frame(width: 1)
                clipColumn
            }
        }
    }

    // MARK: - Search field

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(.white.opacity(0.45))

            TextField("Search apps, clipboard and tabs…", text: Binding(
                get: { vm.searchQuery },
                set: { vm.searchQuery = $0; vm.search() }
            ))
            .textFieldStyle(.plain)
            .font(.system(size: 17, weight: .regular))
            .foregroundStyle(.white)
            .focused($isSearchFocused)
            .tint(.white)

            if !vm.searchQuery.isEmpty {
                Button {
                    vm.searchQuery = ""
                    vm.search()
                    isSearchFocused = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.white.opacity(0.35))
                }
                .buttonStyle(.plain)
                .transition(.opacity.combined(with: .scale(scale: 0.8)))
                .animation(.spring(response: 0.22, dampingFraction: 0.8), value: vm.searchQuery.isEmpty)
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 20)
        .padding(.bottom, 16)
    }

    // MARK: - Apps column (left)

    private var appColumn: some View {
        VStack(spacing: 0) {
            sectionLabel("APPS", active: vm.activePanel == .apps)

            if vm.results.isEmpty && vm.tabResults.isEmpty {
                if vm.showsGoogleFallback {
                    GoogleSearchRow(
                        query: vm.searchQuery,
                        isSelected: vm.activePanel == .apps && vm.selectedIndex == 0
                    )
                    .padding(.horizontal, 6)
                    .padding(.top, 4)
                    .onTapGesture { vm.searchGoogle() }
                    .onHover { if $0 && !vm.ignoreHover { vm.selectedIndex = 0 } }
                } else {
                    emptyLabel("No results")
                }
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 1) {
                        ForEach(Array(vm.results.enumerated()), id: \.element.id) { idx, app in
                            AppResultRow(
                                app: app,
                                isSelected: vm.activePanel == .apps && idx == vm.selectedIndex
                            )
                            .opacity(showContent ? 1 : 0)
                            .offset(y: showContent ? 0 : -6)
                            .animation(
                                .spring(response: 0.28, dampingFraction: 0.80)
                                    .delay(Double(idx) * 0.016),
                                value: showContent
                            )
                            .onTapGesture { vm.selectedIndex = idx; vm.launchApp(app) }
                            .onHover { if $0 && !vm.ignoreHover { vm.selectedIndex = idx } }
                        }

                        if !vm.tabResults.isEmpty {
                            appsSectionDivider("TABS")
                                .padding(.top, 4)

                            let appCount = vm.showsGoogleFallback ? 1 : vm.results.count
                            ForEach(Array(vm.tabResults.enumerated()), id: \.element.id) { idx, tab in
                                let globalIdx = appCount + idx
                                BrowserTabResultRow(
                                    tab: tab,
                                    isSelected: vm.activePanel == .apps && globalIdx == vm.selectedIndex
                                )
                                .opacity(showContent ? 1 : 0)
                                .offset(y: showContent ? 0 : -6)
                                .animation(
                                    .spring(response: 0.28, dampingFraction: 0.80)
                                        .delay(Double(globalIdx) * 0.016),
                                    value: showContent
                                )
                                .onTapGesture { vm.selectedIndex = globalIdx; vm.openTab(tab) }
                                .onHover { if $0 && !vm.ignoreHover { vm.selectedIndex = globalIdx } }
                            }
                        }
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func appsSectionDivider(_ label: String) -> some View {
        HStack(spacing: 6) {
            Rectangle()
                .fill(Color.white.opacity(0.10))
                .frame(height: 0.5)
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.white.opacity(0.25))
                .fixedSize()
            Rectangle()
                .fill(Color.white.opacity(0.10))
                .frame(height: 0.5)
        }
        .padding(.horizontal, 10)
    }

    // MARK: - Clipboard column (right)

    private var clipColumn: some View {
        let clips = vm.filteredClips
        return VStack(spacing: 0) {
            sectionLabel("CLIPBOARD", active: vm.activePanel == .clipboard)
            if clips.isEmpty {
                emptyLabel(clipVM.clips.isEmpty ? "Nothing copied yet" : "No matches")
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 1) {
                        ForEach(Array(clips.enumerated()), id: \.element.id) { idx, clip in
                            ClipResultRow(
                                clip: clip,
                                isSelected: vm.activePanel == .clipboard && idx == vm.clipSelectedIndex,
                                isCopied: vm.copiedClipID == clip.id,
                                showTimestamp: showTimestamps
                            )
                            .opacity(showContent ? 1 : 0)
                            .offset(y: showContent ? 0 : -6)
                            .animation(
                                .spring(response: 0.28, dampingFraction: 0.80)
                                    .delay(Double(idx) * 0.016 + 0.03),
                                value: showContent
                            )
                            .onTapGesture { vm.copyClip(clip) }
                            .onHover { if $0 && !vm.ignoreHover { vm.clipSelectedIndex = idx } }
                            .contextMenu {
                                Button {
                                    clipVM.pin(clip)
                                } label: {
                                    Label(clip.isPinned ? "Unpin" : "Pin",
                                          systemImage: clip.isPinned ? "pin.slash" : "pin")
                                }
                                Divider()
                                Button(role: .destructive) {
                                    clipVM.delete(clip)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // MARK: - Shared helpers

    private func sectionLabel(_ title: String, active: Bool) -> some View {
        HStack(spacing: 5) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(active ? .white.opacity(0.55) : .white.opacity(0.28))
            if active {
                Circle()
                    .fill(.white.opacity(0.45))
                    .frame(width: 4, height: 4)
                    .transition(.scale.combined(with: .opacity))
            }
            Spacer()
        }
        .animation(.spring(response: 0.22, dampingFraction: 0.8), value: active)
        .padding(.horizontal, 14)
        .padding(.top, 8)
        .padding(.bottom, 3)
    }

    private func emptyLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13))
            .foregroundStyle(.white.opacity(0.28))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.vertical, 24)
    }
}

// MARK: - Browser tab result row

private struct BrowserTabResultRow: View {
    let tab: BrowserTab
    let isSelected: Bool

    private var faviconURL: URL? {
        guard let host = URL(string: tab.url)?.host, !host.isEmpty else { return nil }
        return URL(string: "https://www.google.com/s2/favicons?domain=\(host)&sz=32")
    }

    private var browserIcon: NSImage? {
        let bid: String
        switch tab.browser {
        case .safari: bid = "com.apple.Safari"
        case .chrome: bid = "com.google.Chrome"
        case .arc:    bid = "company.thebrowser.Browser"
        }
        return NSRunningApplication.runningApplications(withBundleIdentifier: bid).first?.icon
            ?? NSWorkspace.shared.urlsForApplications(withBundleIdentifier: bid).first
                .map { NSWorkspace.shared.icon(forFile: $0.path) }
    }

    var body: some View {
        HStack(spacing: 9) {
            // Website favicon
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.white.opacity(0.10))
                    .frame(width: 26, height: 26)
                if let url = faviconURL {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let img):
                            img.resizable()
                                .interpolation(.high)
                                .frame(width: 18, height: 18)
                        default:
                            Image(systemName: "globe")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.white.opacity(0.45))
                        }
                    }
                } else {
                    Image(systemName: "globe")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white.opacity(0.45))
                }
            }
            .frame(width: 26, height: 26)

            // Title + URL
            VStack(alignment: .leading, spacing: 1) {
                Text(tab.title.isEmpty ? tab.url : tab.title)
                    .font(.system(size: 13, weight: isSelected ? .medium : .regular))
                    .lineLimit(1)
                Text(tab.url)
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.38))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 4)

            // Saved tag (only for history entries not currently open)
            if tab.isSaved {
                Text("Saved")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.50))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(Color.white.opacity(0.10))
                    )
            }

            // Browser badge
            if let bIcon = browserIcon {
                Image(nsImage: bIcon)
                    .resizable()
                    .frame(width: 14, height: 14)
                    .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                    .opacity(0.7)
            }

            if isSelected {
                Image(systemName: "return")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.white.opacity(0.40))
                    .transition(.opacity.combined(with: .scale(scale: 0.7)))
            }
        }
        .foregroundColor(isSelected ? .white : .white.opacity(0.82))
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isSelected ? Color.white.opacity(0.10) : Color.clear)
        }
        .contentShape(RoundedRectangle(cornerRadius: 8))
        .animation(.spring(response: 0.20, dampingFraction: 0.78), value: isSelected)
    }
}

// MARK: - Google search fallback row

private struct GoogleSearchRow: View {
    let query: String
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color(red: 0.26, green: 0.52, blue: 0.96).opacity(0.85))
                    .frame(width: 26, height: 26)
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text("Search Google")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.40))
                Text(query)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Spacer(minLength: 0)

            if isSelected {
                Image(systemName: "return")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.white.opacity(0.40))
                    .transition(.opacity.combined(with: .scale(scale: 0.7)))
            }
        }
        .foregroundColor(isSelected ? .white : .white.opacity(0.82))
        .padding(.horizontal, 9)
        .padding(.vertical, 8)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isSelected ? Color.white.opacity(0.10) : Color.clear)
        }
        .contentShape(RoundedRectangle(cornerRadius: 8))
        .animation(.spring(response: 0.20, dampingFraction: 0.78), value: isSelected)
    }
}

// MARK: - App result row

private struct AppResultRow: View {
    let app: AppInfo
    let isSelected: Bool

    private static var iconCache: [String: NSImage] = [:]
    private var cachedIcon: NSImage {
        let key = app.bundleURL.path
        if let hit = Self.iconCache[key] { return hit }
        let img = NSWorkspace.shared.icon(forFile: key)
        Self.iconCache[key] = img
        return img
    }

    var body: some View {
        HStack(spacing: 9) {
            Image(nsImage: cachedIcon)
                .resizable()
                .frame(width: 26, height: 26)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

            Text(app.name)
                .font(.system(size: 13, weight: isSelected ? .medium : .regular))
                .lineLimit(1)

            Spacer(minLength: 0)
        }
        .foregroundColor(isSelected ? .white : .white.opacity(0.82))
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isSelected ? Color.white.opacity(0.10) : Color.clear)
        }
        .contentShape(RoundedRectangle(cornerRadius: 8))
        .animation(.spring(response: 0.20, dampingFraction: 0.78), value: isSelected)
        .overlay(alignment: .trailing) {
            if isSelected {
                Image(systemName: "return")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.white.opacity(0.40))
                    .padding(.trailing, 9)
                    .transition(.opacity.combined(with: .scale(scale: 0.7)))
            }
        }
    }
}

// MARK: - Clip result row

private struct ClipResultRow: View {
    let clip: Clip
    let isSelected: Bool
    var isCopied: Bool = false
    var showTimestamp: Bool = false
    @State private var isHovered = false

    private static var appIconCache: [String: NSImage] = [:]
    private var cachedAppIcon: NSImage? {
        guard let bid = clip.sourceAppBundle else { return nil }
        if let hit = Self.appIconCache[bid] { return hit }
        guard let url = NSWorkspace.shared.urlsForApplications(withBundleIdentifier: bid).first else { return nil }
        let img = NSWorkspace.shared.icon(forFile: url.path)
        Self.appIconCache[bid] = img
        return img
    }

    private var previewText: String {
        let raw: String
        switch clip.contentType {
        case .plainText, .url:
            raw = clip.plainText ?? ""
        case .richText:
            raw = clip.attributedString?.string ?? ""
        case .image:
            return "Image\(clip.sourceAppName.map { " · \($0)" } ?? "")"
        }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "—" : trimmed
    }

    var body: some View {
        HStack(spacing: 9) {
            if let appIcon = cachedAppIcon {
                Image(nsImage: appIcon)
                    .resizable()
                    .frame(width: 22, height: 22)
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            } else {
                Image(systemName: fallbackIconName)
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 22, height: 22)
            }

            if isCopied {
                Label("Copied", systemImage: "checkmark")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.green.opacity(0.85))
                    .transition(.opacity.combined(with: .scale(scale: 0.92)))
            } else {
                Text(previewText)
                    .font(.system(size: 13))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .layoutPriority(1)
                    .transition(.opacity)
            }

            Spacer(minLength: 4)

            Text(clip.createdAt.relativeFormatted)
                .font(.system(size: 11))
                .foregroundColor(isCopied ? .green.opacity(0.55) : .white.opacity(0.35))
                .fixedSize()
                .opacity(showTimestamp || isCopied ? 1 : 0)
                .animation(.easeIn(duration: 0.25), value: showTimestamp)
        }
        .foregroundColor(isCopied ? .green.opacity(0.85) : (isSelected || isHovered ? .white : .white.opacity(0.82)))
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isCopied ? Color.green.opacity(0.12) : (isSelected || isHovered) ? Color.white.opacity(0.10) : Color.clear)
        }
        .contentShape(RoundedRectangle(cornerRadius: 8))
        .onHover { isHovered = $0 }
        .animation(.spring(response: 0.22, dampingFraction: 0.80), value: isCopied)
        .animation(.spring(response: 0.20, dampingFraction: 0.78), value: isSelected || isHovered)
    }

    private var fallbackIconName: String {
        switch clip.contentType {
        case .plainText: return "doc.text.fill"
        case .richText:  return "doc.richtext.fill"
        case .url:       return "link"
        case .image:     return "photo.fill"
        }
    }
}

