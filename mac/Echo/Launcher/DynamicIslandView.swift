import SwiftUI
import AppKit

// MARK: - Dimension constants (shared with DynamicIslandWindow for hit-test math)

extension DynamicIslandView {
    static let expandedWidth:  CGFloat = 720
    static let expandedHeight: CGFloat = 440
    static let instantSearchScreenFraction: CGFloat = 0.70

    static func instantSearchSize(for screen: NSScreen?) -> CGSize {
        let frame = screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1280, height: 800)
        return CGSize(
            width: frame.width * instantSearchScreenFraction,
            height: frame.height * instantSearchScreenFraction
        )
    }
}

// MARK: - Main view

struct DynamicIslandView: View {
    @Environment(LauncherViewModel.self) private var vm
    @Environment(LauncherSettings.self) private var launcherSettings
    @Environment(ClipViewModel.self)     private var clipVM
    @Environment(InstantSearchSession.self) private var instantSession
    @Environment(RemoteConfigService.self) private var remoteConfig
    @FocusState private var isSearchFocused: Bool

    @State private var showContent    = false
    @State private var showTimestamps = false
    @State private var instantSearchAnimating = false
    @State private var promoDismissedLocally = false
    @State private var instantSearchScale: CGFloat = 1.0

    private static let launcherSpring = Animation.spring(response: 0.34, dampingFraction: 0.78)
    private static let launcherSpringBouncy = Animation.spring(response: 0.34, dampingFraction: 0.72)
    /// Quick spring for result rows re-sorting as the user types.
    private static let listSpring = Animation.spring(response: 0.28, dampingFraction: 0.86)
    /// Single spring for open/close — matched to `DynamicIslandWindow.show()`.
    private static let openSpring = Animation.spring(response: 0.38, dampingFraction: 0.88)

    private var cr: CGFloat {
        vm.isInstantSearchOpen ? 20 : 24
    }

    private func islandW(_ geo: GeometryProxy) -> CGFloat {
        if vm.isInstantSearchOpen {
            return Self.instantSearchSize(for: NSScreen.main).width
        }
        return Self.expandedWidth
    }
    private func islandH(_ geo: GeometryProxy) -> CGFloat {
        if vm.isInstantSearchOpen {
            return Self.instantSearchSize(for: NSScreen.main).height
        }
        return Self.expandedHeight
    }

    private var islandScale: CGFloat {
        guard vm.isVisible else { return 0.90 }
        if vm.isInstantSearchOpen { return instantSearchScale }
        return 1.0
    }

    /// 3D tilt used on open — leans back when hidden, settles flat when visible.
    private var islandTiltDegrees: Double {
        vm.isVisible ? 0 : -14
    }

    /// 2D skew + slight vertical shift for a card-like open.
    private var islandSkewTransform: CGAffineTransform {
        guard vm.isVisible else {
            return CGAffineTransform(a: 0.92, b: 0, c: -0.095, d: 0.90, tx: 0, ty: -12)
        }
        return .identity
    }

    private var islandVerticalOffset: CGFloat {
        vm.isVisible ? 0 : -14
    }

    /// Always scale from the geometric center of the island so the open
    /// animation grows uniformly outward instead of unfurling from the top.
    private var islandScaleAnchor: UnitPoint { .center }

    var body: some View {
        GeometryReader { geo in
            islandRoot(geo)
                .frame(
                    maxWidth: .infinity,
                    maxHeight: .infinity,
                    alignment: vm.isInstantSearchOpen ? .center : .top
                )
        }
        .onChange(of: vm.isExpanded) { _, expanded in
            if expanded {
                vm.expand()
                showContent = true
                showTimestamps = true
                isSearchFocused = true
            } else {
                showContent = false
                isSearchFocused = false
                showTimestamps = false
            }
        }
        .onChange(of: launcherSettings.showTabsInSearch) { _, enabled in
            if enabled {
                vm.warmTabsCache()
                if vm.isExpanded { vm.expand() }
            } else {
                vm.clearTabResults()
            }
            vm.search()
        }
        .onChange(of: vm.isInstantSearchOpen) { _, open in
            if open {
                isSearchFocused = false
                instantSearchAnimating = false
                instantSearchScale = 0.86
                withAnimation(Self.launcherSpringBouncy) {
                    instantSearchScale = 1.0
                }
                Task {
                    try? await Task.sleep(for: .milliseconds(140))
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.84)) {
                        instantSearchAnimating = true
                    }
                }
            } else {
                instantSearchAnimating = false
                withAnimation(Self.launcherSpring) {
                    instantSearchScale = 1.0
                }
                Task {
                    try? await Task.sleep(for: .milliseconds(120))
                    isSearchFocused = true
                }
            }
        }
    }

    private func islandRoot(_ geo: GeometryProxy) -> some View {
        ZStack {
            islandBackground
            if showContent {
                expandedContent
                    .transition(.opacity.animation(Self.openSpring))
            }
        }
        .environment(\.colorScheme, .dark)
        .frame(width: islandW(geo), height: islandH(geo))
        .offset(y: islandVerticalOffset)
        .rotation3DEffect(
            .degrees(islandTiltDegrees),
            axis: (x: 1, y: -0.18, z: 0),
            anchor: islandScaleAnchor,
            perspective: 0.52
        )
        .transformEffect(islandSkewTransform)
        .scaleEffect(islandScale, anchor: islandScaleAnchor)
        .opacity(vm.isVisible ? 1.0 : 0)
        .animation(Self.launcherSpring, value: vm.isInstantSearchOpen)
        .animation(vm.isVisible ? Self.openSpring : nil, value: vm.isVisible)
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
            .animation(Self.launcherSpring, value: vm.isInstantSearchOpen)
    }

    // MARK: - Expanded content

    private var expandedContent: some View {
        Group {
            if vm.isInstantSearchOpen {
                instantSearchPanel
                    .transition(
                        .asymmetric(
                            insertion: .opacity.combined(with: .scale(scale: 0.92, anchor: .center)),
                            removal: .opacity.combined(with: .scale(scale: 0.96, anchor: .center))
                        )
                    )
            } else {
                VStack(spacing: 0) {
                    searchField
                        .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .center)))

                    if shouldShowPromo {
                        PromoBannerView(
                            promo: remoteConfig.promo,
                            onLinkTap: {},
                            onDismiss: { promoDismissedLocally = true }
                        )
                        .transition(.opacity.combined(with: .move(edge: .top)))
                        .onChange(of: remoteConfig.promo.id) { _, _ in
                            promoDismissedLocally = false
                        }
                    }

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
                    .frame(maxHeight: .infinity)
                }
                .transition(.opacity)
            }
        }
        .animation(Self.launcherSpring, value: vm.isInstantSearchOpen)
    }

    private var shouldShowPromo: Bool {
        let promo = remoteConfig.promo
        return promo.enabled
            && !PromoDismissStore.isDismissed(promoID: promo.id)
            && !promoDismissedLocally
            && !vm.isSearching
    }

    private var instantSearchPanel: some View {
        VStack(spacing: 0) {
            InstantSearchChrome()
            Rectangle()
                .fill(Color.white.opacity(0.07))
                .frame(height: 1)
            InstantSearchWebView(webView: instantSession.webView)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .opacity(instantSearchAnimating ? 1 : 0)
                .animation(.spring(response: 0.28, dampingFraction: 0.84).delay(0.05), value: instantSearchAnimating)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Search field

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(.white.opacity(0.45))

            TextField("Search apps, clipboard, or calculate…", text: Binding(
                get: { vm.searchQuery },
                set: { vm.searchQuery = $0; vm.search() }
            ))
            .textFieldStyle(.plain)
            .font(.system(size: 17, weight: .regular))
            .foregroundStyle(.white)
            .focused($isSearchFocused)
            .tint(.white)

            if vm.utilityIsLoading {
                ProgressView()
                    .controlSize(.small)
                    .tint(.white.opacity(0.5))
            } else if let error = vm.utilityError {
                Text(error)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.orange.opacity(0.85))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            } else if let utility = vm.utilityResult {
                Text(utility.previewText)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .transition(.opacity)
                    .animation(.easeOut(duration: 0.12), value: utility.previewText)
            }

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

            Button {
                vm.openDashboard()
            } label: {
                Image(systemName: "square.grid.2x2.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.72))
                    .frame(width: 28, height: 28)
                    .background(
                        Circle()
                            .fill(.white.opacity(0.12))
                    )
            }
            .buttonStyle(.plain)
            .help("Open Dashboard")
        }
        .padding(.horizontal, 14)
        .padding(.top, 20)
        .padding(.bottom, 16)
    }

    // MARK: - Apps column (left)

    private var appColumn: some View {
        let calcOffset = vm.utilityRowCount
        let hasContent = vm.isSearching
            ? !vm.mixedSearchResults.isEmpty
            : !vm.results.isEmpty
                || (launcherSettings.showTabsInSearch && (!vm.defaultTabResults.isEmpty || vm.tabsAreLoading))
        return VStack(spacing: 0) {
            sectionLabel(vm.isSearching ? "RESULTS" : "APPS", active: vm.activePanel == .apps)

            if !hasContent && !vm.showsUtilityRow {
                if vm.showsGoogleFallback {
                    VStack(spacing: 1) {
                        fallbackRows(baseOffset: calcOffset)
                    }
                    .padding(.horizontal, 6)
                    .padding(.top, 4)
                } else {
                    emptyLabel("No results")
                }
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 1) {
                        if vm.showsUtilityRow {
                            UtilityResultRow(
                                query: vm.searchQuery,
                                result: vm.utilityResult,
                                isLoading: vm.utilityIsLoading,
                                errorMessage: vm.utilityError,
                                isSelected: vm.activePanel == .apps && vm.selectedIndex == 0
                            )
                            .onTapGesture {
                                vm.selectedIndex = 0
                                vm.copyUtilityResult()
                            }
                            .onHover { if $0 && !vm.ignoreHover { vm.selectedIndex = 0 } }
                        }

                        if vm.results.isEmpty && vm.tabResults.isEmpty && vm.showsGoogleFallback {
                            fallbackRows(baseOffset: calcOffset)
                        }

                        if vm.isSearching {
                            ForEach(Array(vm.mixedSearchResults.enumerated()), id: \.element.id) { idx, item in
                                let globalIdx = calcOffset + idx
                                mixedSearchRow(item, globalIdx: globalIdx)
                            }
                        } else {
                            ForEach(Array(vm.results.enumerated()), id: \.element.id) { idx, app in
                                let globalIdx = calcOffset + idx
                                AppResultRow(
                                    app: app,
                                    isSelected: vm.activePanel == .apps && globalIdx == vm.selectedIndex,
                                    isLaunching: vm.launchingAppID == app.id
                                )
                                .onTapGesture { vm.selectedIndex = globalIdx; vm.launchApp(app) }
                                .onHover { if $0 && !vm.ignoreHover { vm.selectedIndex = globalIdx } }
                            }

                            if launcherSettings.showTabsInSearch,
                               !vm.defaultTabResults.isEmpty || vm.tabsAreLoading {
                                tabsSectionLabel
                                    .padding(.top, 4)

                                if vm.tabsAreLoading && vm.defaultTabResults.isEmpty {
                                    tabsLoadingRow
                                }

                                ForEach(Array(vm.defaultTabResults.enumerated()), id: \.element.id) { idx, tab in
                                    let globalIdx = calcOffset + vm.results.count + idx
                                    BrowserTabResultRow(
                                        tab: tab,
                                        isSelected: vm.activePanel == .apps && globalIdx == vm.selectedIndex,
                                        isLive: !tab.isSaved
                                    )
                                    .onTapGesture { vm.selectedIndex = globalIdx; vm.openTab(tab) }
                                    .onHover { if $0 && !vm.ignoreHover { vm.selectedIndex = globalIdx } }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .animation(Self.listSpring, value: appListAnimationKey)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    /// Identity of every visible row in the apps column, in display order.
    /// Rows keep their IDs across keystrokes, so animating on this key makes
    /// SwiftUI slide surviving rows to their new positions instead of redrawing.
    private var appListAnimationKey: [String] {
        var key: [String] = []
        if vm.showsUtilityRow { key.append("utility") }
        if vm.showsGoogleFallback {
            key.append(vm.instantSearchFirst ? "fallback-instant-first" : "fallback-google-first")
        }
        if vm.isSearching {
            key.append(contentsOf: vm.mixedSearchResults.map(\.id))
        } else {
            key.append(contentsOf: vm.results.map { "app-\($0.id.uuidString)" })
            if launcherSettings.showTabsInSearch {
                key.append(contentsOf: vm.defaultTabResults.map { "tab-\($0.id)" })
            }
        }
        return key
    }

    @ViewBuilder
    private func mixedSearchRow(_ item: LauncherSearchItem, globalIdx: Int) -> some View {
        switch item {
        case .app(let app):
            AppResultRow(
                app: app,
                isSelected: vm.activePanel == .apps && globalIdx == vm.selectedIndex,
                isLaunching: vm.launchingAppID == app.id
            )
            .onTapGesture { vm.selectedIndex = globalIdx; vm.launchApp(app) }
            .onHover { if $0 && !vm.ignoreHover { vm.selectedIndex = globalIdx } }
        case .tab(let tab):
            BrowserTabResultRow(
                tab: tab,
                isSelected: vm.activePanel == .apps && globalIdx == vm.selectedIndex,
                isLive: !tab.isSaved
            )
            .onTapGesture { vm.selectedIndex = globalIdx; vm.openTab(tab) }
            .onHover { if $0 && !vm.ignoreHover { vm.selectedIndex = globalIdx } }
        }
    }

    @ViewBuilder
    private func fallbackRows(baseOffset: Int) -> some View {
        if vm.instantSearchFirst {
            instantSearchRow(at: baseOffset)
            googleRow(at: baseOffset + 1)
        } else {
            googleRow(at: baseOffset)
            instantSearchRow(at: baseOffset + 1)
        }
    }

    private func instantSearchRow(at index: Int) -> some View {
        InstantSearchResultRow(
            query: vm.searchQuery,
            hostLabel: vm.instantSearchHostLabel,
            isDomain: vm.isDomainQuery,
            isSelected: vm.activePanel == .apps && vm.selectedIndex == index,
            isLoading: instantSession.isLoading && vm.isInstantSearchOpen
        )
        .onTapGesture { vm.selectedIndex = index; vm.openInstantSearch() }
        .onHover { if $0 && !vm.ignoreHover { vm.selectedIndex = index } }
    }

    private func googleRow(at index: Int) -> some View {
        GoogleSearchRow(
            query: vm.searchQuery,
            isSelected: vm.activePanel == .apps && vm.selectedIndex == index,
            isDomain: vm.isDomainQuery
        )
        .onTapGesture { vm.selectedIndex = index; vm.searchGoogle() }
        .onHover { if $0 && !vm.ignoreHover { vm.selectedIndex = index } }
    }

    private var tabsSectionLabel: some View {
        HStack(spacing: 5) {
            Text("TABS")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.28))
            Circle()
                .fill(Color.green.opacity(0.88))
                .frame(width: 5, height: 5)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.top, 4)
        .padding(.bottom, 3)
    }

    private var tabsLoadingRow: some View {
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
                .tint(.white.opacity(0.55))
            Text("Loading open tabs…")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.42))
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    // MARK: - Clipboard column (right)

    private var clipColumn: some View {
        let clips = vm.filteredClips
        return VStack(spacing: 0) {
            HStack(spacing: 8) {
                sectionLabel("CLIPBOARD", active: vm.activePanel == .clipboard)
                Spacer(minLength: 0)
                PlainTextPasteToggle(style: .launcherColumn)
            }
            .padding(.trailing, 10)
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
                            .onTapGesture { vm.copyClip(clip) }
                            .onHover { if $0 && !vm.ignoreHover { vm.clipSelectedIndex = idx } }
                            .contextMenu {
                                Button { vm.copyClip(clip) } label: {
                                    Label("Copy", systemImage: "doc.on.doc")
                                }
                                if clip.supportsPlainTextCopy {
                                    Button { vm.copyClipAsPlainText(clip) } label: {
                                        Label("Copy as Plain Text", systemImage: "doc.plaintext")
                                    }
                                }
                                Divider()
                                Button { clipVM.pin(clip, surface: "launcher") } label: {
                                    Label(clip.isPinned ? "Unpin" : "Pin",
                                          systemImage: clip.isPinned ? "pin.slash" : "pin")
                                }
                                Divider()
                                Button(role: .destructive) { clipVM.delete(clip, surface: "launcher") } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .animation(Self.listSpring, value: clips.map(\.id))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
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
    var isLive: Bool = false

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
            .overlay(alignment: .bottomTrailing) {
                if isLive {
                    Circle()
                        .fill(Color.green.opacity(0.92))
                        .frame(width: 7, height: 7)
                        .overlay {
                            Circle()
                                .stroke(Color.black.opacity(0.35), lineWidth: 0.8)
                        }
                        .offset(x: 2, y: 2)
                }
            }

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

// MARK: - Utility result row

private struct UtilityResultRow: View {
    let query: String
    let result: UtilityResult?
    let isLoading: Bool
    let errorMessage: String?
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(accentColor.opacity(0.85))
                    .frame(width: 26, height: 26)
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.white)
                } else {
                    Image(systemName: iconName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(query)
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.40))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(primaryLine)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                if let detail = detailLine {
                    Text(detail)
                        .font(.system(size: 10))
                        .foregroundColor(detailColor)
                        .lineLimit(2)
                        .truncationMode(.tail)
                }
            }

            Spacer(minLength: 0)

            if isSelected, !isLoading, result?.copyText.isEmpty == false {
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

    private var iconName: String {
        result?.kind.systemImage ?? "dollarsign.arrow.circlepath"
    }

    private var primaryLine: String {
        if isLoading { return "Fetching rates…" }
        if let errorMessage { return errorMessage }
        return result?.previewText ?? "—"
    }

    private var detailLine: String? {
        if errorMessage != nil, let result { return result.detailText }
        return result?.detailText
    }

    private var detailColor: Color {
        errorMessage != nil ? .orange.opacity(0.75) : .white.opacity(0.42)
    }

    private var accentColor: Color {
        switch result?.kind {
        case .calculation:    return Color(red: 0.35, green: 0.55, blue: 0.95)
        case .percentage:     return Color(red: 0.35, green: 0.72, blue: 0.45)
        case .unitConversion: return Color(red: 0.55, green: 0.45, blue: 0.92)
        case .dateTime:       return Color(red: 0.92, green: 0.55, blue: 0.32)
        case .timestamp:      return Color(red: 0.32, green: 0.72, blue: 0.88)
        case .currency:       return Color(red: 0.28, green: 0.78, blue: 0.52)
        case .none:           return Color(red: 0.28, green: 0.78, blue: 0.52)
        }
    }
}

// MARK: - Google search / domain navigation fallback row

private struct GoogleSearchRow: View {
    let query: String
    let isSelected: Bool
    let isDomain: Bool

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(iconColor.opacity(0.85))
                    .frame(width: 26, height: 26)
                Image(systemName: isDomain ? "safari" : "magnifyingglass")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(isDomain ? "Open in Browser" : "Search Google")
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
        .animation(.easeInOut(duration: 0.15), value: isDomain)
    }

    private var iconColor: Color {
        isDomain
            ? Color(red: 0.13, green: 0.65, blue: 0.53)   // teal for browser
            : Color(red: 0.26, green: 0.52, blue: 0.96)    // blue for Google
    }
}

// MARK: - App result row

private struct AppResultRow: View {
    let app: AppInfo
    let isSelected: Bool
    var isLaunching: Bool = false

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
                .fill(isLaunching || isSelected ? Color.white.opacity(0.10) : Color.clear)
        }
        .contentShape(RoundedRectangle(cornerRadius: 8))
        .animation(.spring(response: 0.20, dampingFraction: 0.78), value: isSelected)
        .animation(.easeInOut(duration: 0.18), value: isLaunching)
        .overlay(alignment: .trailing) {
            Group {
                if isLaunching {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.white.opacity(0.55))
                        .padding(.trailing, 9)
                        .transition(.opacity.combined(with: .scale(scale: 0.85)))
                } else if isSelected {
                    Image(systemName: "return")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.white.opacity(0.40))
                        .padding(.trailing, 9)
                        .transition(.opacity.combined(with: .scale(scale: 0.7)))
                }
            }
        }
    }
}

// MARK: - Clip result row

private struct ClipResultRow: View {
    @Environment(ClipViewModel.self) private var clipVM
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
        if clip.isLink, let title = clip.linkTitle, !title.isEmpty {
            return title
        }
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
            leadingIcon

            if isCopied {
                Label("Copied", systemImage: "checkmark")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.green.opacity(0.85))
                    .transition(.opacity.combined(with: .scale(scale: 0.92)))
            } else if clip.parsedColor != nil {
                Text(previewText)
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .layoutPriority(1)
                    .transition(.opacity)
            } else {
                Text(previewText)
                    .font(.system(size: 13))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .layoutPriority(1)
                    .transition(.opacity)
            }

            Spacer(minLength: 4)

            // Pin: always shown when pinned; appears on hover to pin/unpin.
            if isHovered || clip.isPinned {
                Button {
                    clipVM.pin(clip, surface: "launcher")
                } label: {
                    Image(systemName: clip.isPinned ? "pin.fill" : "pin")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(clip.isPinned ? .orange : .white.opacity(0.50))
                        .frame(width: 18, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(clip.isPinned ? "Unpin" : "Pin — pinned clips never expire")
                .transition(.opacity)
            }

            if showsTypeTag {
                trailingTypeTag
            }

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

    // MARK: - Leading icon + type tag

    @ViewBuilder
    private var leadingIcon: some View {
        if let appIcon = cachedAppIcon {
            Image(nsImage: appIcon)
                .resizable()
                .frame(width: 22, height: 22)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        } else if let color = clip.parsedColor {
            colorCircle(size: 22)
        } else if showsTypeTag {
            standaloneTypeBadge
        } else {
            Image(systemName: fallbackIconName)
                .font(.system(size: 12, weight: .medium))
                .frame(width: 22, height: 22)
        }
    }

    private var showsTypeTag: Bool {
        clip.parsedColor != nil || clip.autoTag == .link || clip.autoTag == .code
    }

    @ViewBuilder
    private var trailingTypeTag: some View {
        Group {
            if clip.parsedColor != nil {
                colorCircle(size: 14)
            } else if clip.autoTag == .link {
                tagGlyph("link", tint: .blue, size: 14, symbolSize: 7)
            } else if clip.autoTag == .code {
                tagGlyph("chevron.left.forwardslash.chevron.right",
                         tint: Color(red: 0.55, green: 0.35, blue: 0.95),
                         size: 14, symbolSize: 6)
            }
        }
        .fixedSize()
    }

    private var standaloneTypeBadge: some View {
        Group {
            if clip.autoTag == .link {
                tagGlyph("link", tint: .blue, size: 22, symbolSize: 10)
            } else {
                tagGlyph("chevron.left.forwardslash.chevron.right",
                         tint: Color(red: 0.55, green: 0.35, blue: 0.95),
                         size: 22, symbolSize: 9)
            }
        }
    }

    private func tagGlyph(
        _ symbol: String,
        tint: Color,
        size: CGFloat = 10,
        symbolSize: CGFloat = 5.5
    ) -> some View {
        Image(systemName: symbol)
            .font(.system(size: symbolSize, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Circle().fill(tint.opacity(0.85)))
            .overlay(Circle().stroke(Color.black.opacity(0.30), lineWidth: 0.8))
    }

    private func colorCircle(size: CGFloat) -> some View {
        let color = clip.parsedColor ?? .gray
        let isLight = color.perceivedBrightness > 0.78
        return Circle()
            .fill(Color(nsColor: color))
            .frame(width: size, height: size)
            .overlay {
                Circle()
                    .stroke(Color.white.opacity(isLight ? 0.28 : 0.18), lineWidth: 0.6)
            }
    }

    private var fallbackIconName: String {
        switch clip.autoTag {
        case .color:    return "paintpalette.fill"
        case .image:    return "photo.fill"
        case .richText: return "doc.richtext.fill"
        case .code:     return "chevron.left.forwardslash.chevron.right"
        default:        return "doc.text.fill"
        }
    }
}

// MARK: - Hex color swatch

/// Small filled square that previews a hex-color clip. A subtle hairline border
/// keeps very light or very dark swatches readable against the launcher background.
struct HexColorSwatch: View {
    let color: NSColor

    var body: some View {
        let isLight = color.perceivedBrightness > 0.78
        RoundedRectangle(cornerRadius: 5, style: .continuous)
            .fill(Color(nsColor: color))
            .overlay {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .stroke(
                        Color.white.opacity(isLight ? 0.22 : 0.18),
                        lineWidth: 0.6
                    )
            }
    }
}

