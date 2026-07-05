import AppKit
import Observation

enum LauncherSearchItem: Identifiable {
    case app(AppInfo)
    case tab(BrowserTab)

    var id: String {
        switch self {
        case .app(let app): return "app-\(app.id.uuidString)"
        case .tab(let tab): return "tab-\(tab.id.uuidString)"
        }
    }
}

@Observable
@MainActor
final class LauncherViewModel {
    var searchQuery: String = ""
    var results: [AppInfo] = []
    var tabResults: [BrowserTab] = []
    var selectedIndex: Int = 0
    var clipSelectedIndex: Int = 0
    var activePanel: ActivePanel = .apps
    var isExpanded: Bool = false
    var isVisible: Bool = false
    var copiedClipID: UUID? = nil
    /// Set to the row id of the app being launched while we're waiting for the
    /// system to finish bringing it up. The row swaps its ↩︎ affordance for a
    /// spinner so the user gets immediate feedback for slow-launching apps.
    var launchingAppID: UUID? = nil
    var utilityResult: UtilityResult? = nil
    var utilityIsLoading: Bool = false
    var utilityError: String? = nil
    var ignoreHover: Bool = true
    var isInstantSearchOpen: Bool = false
    /// When both Instant Search and Google rows show, usage picks which appears first.
    var instantSearchFirst: Bool = true
    var tabsAreLoading: Bool = false

    let instantSearchSession = InstantSearchSession()

    private var utilityResolveTask: Task<Void, Never>?

    var onDismiss: (() -> Void)?
    var onLaunch:  (() -> Void)?
    var onOpenDashboard: (() -> Void)?
    var onInstantSearchChanged: ((Bool) -> Void)?

    var clipVM: ClipViewModel?

    private let engine    = AppSearchEngine()
    private let tabEngine = BrowserTabEngine()
    private let tabStore  = BrowserTabStore()

    private var cachedAllTabs: [BrowserTab] = []
    private var cachedActiveTabs: [BrowserTab] = []
    private var tabPollerTask: Task<Void, Never>?
    private var appIndexWatcher: AppIndexWatcher?

    enum ActivePanel { case apps, clipboard }

    private static let clipboardDisplayLimit = 250

    // MARK: - Derived

    var filteredClips: [Clip] {
        guard let clipVM else { return [] }
        let query = searchQuery.lowercased()
        let matched: [Clip]
        if query.isEmpty {
            matched = clipVM.clips
        } else {
            matched = clipVM.clips.filter { clipMatches($0, query: query) }
        }
        return Array(matched.prefix(Self.clipboardDisplayLimit))
    }

    private func clipMatches(_ clip: Clip, query: String) -> Bool {
        if clip.plainText?.lowercased().contains(query) == true { return true }
        if clip.attributedString?.string.lowercased().contains(query) == true { return true }
        if clip.sourceAppName?.lowercased().contains(query) == true { return true }
        return false
    }

    var showsGoogleFallback: Bool {
        !searchQuery.isEmpty && results.isEmpty && tabResults.isEmpty
    }

    var showsInstantSearchRow: Bool { showsGoogleFallback }

    var instantSearchRowCount: Int { showsInstantSearchRow ? 1 : 0 }

    var googleFallbackRowCount: Int { showsGoogleFallback ? 1 : 0 }

    var webFallbackRowCount: Int {
        guard showsGoogleFallback else { return 0 }
        return instantSearchRowCount + googleFallbackRowCount
    }

    var instantSearchHostLabel: String {
        InstantSearchURLResolver.displayHost(for: searchQuery, isDomainQuery: isDomainQuery)
    }

    var instantSearchTargetURL: URL? {
        InstantSearchURLResolver.targetURL(for: searchQuery, isDomainQuery: isDomainQuery)
    }

    var showsUtilityRow: Bool {
        utilityResult != nil || utilityIsLoading || utilityError != nil
    }

    var utilityRowCount: Int { showsUtilityRow ? 1 : 0 }

    var isSearching: Bool { !searchQuery.trimmingCharacters(in: .whitespaces).isEmpty }

    /// Currently open browser tabs from the latest search results.
    var liveTabResults: [BrowserTab] { tabResults.filter { !$0.isSaved } }

    /// Saved/history tabs from the latest search results (excludes URLs that are open).
    var savedTabResults: [BrowserTab] { tabResults.filter { $0.isSaved } }

    /// Default launcher view: active tabs first, then saved history.
    var defaultTabResults: [BrowserTab] {
        guard !isSearching else { return [] }
        return tabResults
    }

    /// While searching: interleave apps with live tabs, then append saved matches.
    var mixedSearchResults: [LauncherSearchItem] {
        guard isSearching else { return [] }
        var items = Self.interleaveAppsAndTabs(apps: results, tabs: liveTabResults)
        items.append(contentsOf: savedTabResults.map { .tab($0) })
        return items
    }

    var combinedCount: Int {
        if showsGoogleFallback { return utilityRowCount + webFallbackRowCount }
        if isSearching { return utilityRowCount + mixedSearchResults.count }
        return utilityRowCount + results.count + defaultTabResults.count
    }

    init() {
        Task {
            await engine.indexApps()
            await refreshDefaults()
        }
        appIndexWatcher = AppIndexWatcher(paths: AppSearchEngine.applicationDirectoryPaths) { [weak self] in
            Task { @MainActor in
                await self?.reindexApps()
            }
        }
    }

    // MARK: - Search

    func search() {
        selectedIndex     = 0
        clipSelectedIndex = 0
        resolveUtility()
        let trimmed = searchQuery.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty {
            AnalyticsService.logSearchQuery(length: trimmed.count)
        }
        Task {
            results = await engine.search(query: searchQuery)
            instantSearchFirst = !(await InstantSearchUsageStore.shared.prefersGoogleOverInstant)
        }
        tabResults = tabEngine.search(query: searchQuery, in: cachedAllTabs)
        if let url = instantSearchTargetURL {
            if isInstantSearchOpen {
                instantSearchSession.load(url)
            } else if showsInstantSearchRow {
                instantSearchSession.prefetch(url: url)
            }
        }
    }

    private func resolveUtility() {
        utilityResolveTask?.cancel()

        if let currencyQuery = CurrencyQueryParser.parse(searchQuery) {
            resolveCurrencyUtility(currencyQuery)
            return
        }

        utilityIsLoading = false
        utilityError = nil
        utilityResult = UtilityParser.parse(searchQuery)
        trackUtilityResult(utilityResult)
    }

    private func resolveCurrencyUtility(_ query: CurrencyQuery) {
        let service = CurrencyConversionService.shared

        if let cached = service.peekCached(query: query) {
            utilityResult = cached
            utilityIsLoading = false
            utilityError = nil
            utilityResolveTask = Task {
                await service.refreshIfStale(base: query.fromCode, target: query.toCode)
                guard !Task.isCancelled else { return }
                if let updated = service.peekCached(query: query) {
                    utilityResult = updated
                }
            }
            return
        }

        utilityIsLoading = true
        utilityError = nil
        utilityResult = CurrencyConversionEngine.loadingPlaceholder(query: query)

        utilityResolveTask = Task {
            do {
                let result = try await service.convert(query)
                guard !Task.isCancelled else { return }
                utilityIsLoading = false
                utilityError = nil
                utilityResult = result
                trackUtilityResult(result)
            } catch {
                guard !Task.isCancelled else { return }
                utilityIsLoading = false
                if let fallback = service.peekCached(query: query) {
                    utilityError = "Offline — showing cached rate"
                    utilityResult = fallback
                    trackUtilityResult(fallback)
                } else {
                    utilityError = error.localizedDescription
                    utilityResult = nil
                }
            }
        }
    }

    func refreshDefaults() async {
        results = await engine.search(query: "")
    }

    /// Rebuilds the installed-app index (e.g. after a new install) and refreshes visible results.
    func reindexApps() async {
        await engine.indexApps()
        results = await engine.search(query: searchQuery)
    }

    func refreshTabs() async {
        // Fetch live tabs, persist them, then merge with saved history.
        let activeTabs = await tabEngine.fetchTabs()
        for tab in activeTabs { await tabStore.save(tab) }
        await tabStore.prune()

        let savedTabs  = await tabStore.fetchAll()
        let activeURLs = Set(activeTabs.map(\.url))
        // Saved-only tabs (not currently open) get the isSaved flag already set.
        let savedOnly  = savedTabs.filter { !activeURLs.contains($0.url) }

        cachedActiveTabs = activeTabs
        cachedAllTabs = activeTabs + savedOnly
        tabResults = tabEngine.search(query: searchQuery, in: cachedAllTabs)
    }

    /// Loads saved tab history from SQLite — fast path shown while live tabs fetch.
    private func preloadSavedTabs() async {
        let savedTabs = await tabStore.fetchAll()
        let activeURLs = Set(cachedActiveTabs.map(\.url))
        let savedOnly = savedTabs.filter { !activeURLs.contains($0.url) }
        cachedAllTabs = cachedActiveTabs + savedOnly
        tabResults = tabEngine.search(query: searchQuery, in: cachedAllTabs)
    }

    /// Background warm-up so the first launcher open may already have tab data.
    func warmTabsCache() {
        Task { await refreshTabs() }
    }

    // MARK: - Panel switching

    func switchPanel() {
        activePanel = (activePanel == .apps) ? .clipboard : .apps
        AnalyticsService.logLauncherPanelSwitched(panel: activePanel == .apps ? "apps" : "clipboard")
        if activePanel == .clipboard { clipSelectedIndex = 0 }
    }

    /// Handles Escape with nested dismiss: instant search → clipboard → launcher.
    /// Returns `true` when the key press was consumed without closing the launcher.
    func handleEscape() -> Bool {
        if isInstantSearchOpen {
            closeInstantSearch()
            return true
        }
        if activePanel == .clipboard {
            activePanel = .apps
            return true
        }
        return false
    }

    // MARK: - Navigation

    func selectNext() {
        switch activePanel {
        case .apps:
            let last = max(0, combinedCount - 1)
            selectedIndex = min(selectedIndex + 1, last)
        case .clipboard:
            clipSelectedIndex = min(clipSelectedIndex + 1, max(0, filteredClips.count - 1))
        }
    }

    func selectPrevious() {
        switch activePanel {
        case .apps:
            selectedIndex = max(selectedIndex - 1, 0)
        case .clipboard:
            clipSelectedIndex = max(clipSelectedIndex - 1, 0)
        }
    }

    // MARK: - Domain detection

    /// Matches bare domains and URLs with an optional scheme, port, and path.
    /// Requires at least one dot followed by 2+ letter TLD; rejects strings with spaces.
    private static let domainRegex = try? NSRegularExpression(
        pattern: #"^(https?://)?([a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z]{2,}(:\d{1,5})?(\/[^\s]*)?$"#
    )

    var isDomainQuery: Bool {
        guard !searchQuery.isEmpty, !searchQuery.contains(" ") else { return false }
        let r = NSRange(searchQuery.startIndex..., in: searchQuery)
        return Self.domainRegex?.firstMatch(in: searchQuery, range: r) != nil
    }

    // MARK: - Actions

    func openDomain() {
        AnalyticsService.logDomainOpened()
        var raw = searchQuery.trimmingCharacters(in: .whitespaces)
        if !raw.hasPrefix("http://") && !raw.hasPrefix("https://") {
            raw = "https://" + raw
        }
        guard let url = URL(string: raw) else { return }
        NSWorkspace.shared.open(url)
        onLaunch?()
    }

    func searchGoogle() {
        Task { await InstantSearchUsageStore.shared.recordGoogleOpen() }
        if isDomainQuery { openDomain(); return }
        AnalyticsService.logGoogleSearchOpened()
        guard !searchQuery.isEmpty,
              let encoded = searchQuery.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://www.google.com/search?q=\(encoded)")
        else { return }
        NSWorkspace.shared.open(url)
        onLaunch?()
    }

    func openInstantSearch() {
        guard let url = instantSearchTargetURL else { return }
        AnalyticsService.logInstantSearchOpened()
        instantSearchSession.load(url)
        isInstantSearchOpen = true
        onInstantSearchChanged?(true)
        let host = url.host ?? ""
        Task { await InstantSearchUsageStore.shared.recordInstantOpen(host: host) }
    }

    func closeInstantSearch() {
        guard isInstantSearchOpen else { return }
        isInstantSearchOpen = false
        AnalyticsService.logInstantSearchClosed()
        onInstantSearchChanged?(false)
    }

    func confirmInstantSearchSelection(at contentIndex: Int) {
        guard showsGoogleFallback else { return }
        if showsInstantSearchRow {
            if instantSearchFirst {
                if contentIndex == 0 { openInstantSearch(); return }
                if contentIndex == 1 { searchGoogle(); return }
            } else {
                if contentIndex == 0 { searchGoogle(); return }
                if contentIndex == 1 { openInstantSearch(); return }
            }
        } else {
            searchGoogle()
        }
    }

    func confirmSelected() {
        switch activePanel {
        case .apps:
            if showsUtilityRow, selectedIndex == 0 {
                copyUtilityResult()
                return
            }
            let contentIndex = selectedIndex - utilityRowCount
            if showsGoogleFallback {
                confirmInstantSearchSelection(at: contentIndex)
                return
            }
            if isSearching {
                activateMixedSearchItem(at: contentIndex)
                return
            }
            if contentIndex < results.count {
                launchApp(results[contentIndex])
            } else {
                let tabIdx = contentIndex - results.count
                guard defaultTabResults.indices.contains(tabIdx) else { return }
                openTab(defaultTabResults[tabIdx])
            }
        case .clipboard:
            let clips = filteredClips
            guard clips.indices.contains(clipSelectedIndex) else { return }
            copyClip(clips[clipSelectedIndex])
        }
    }

    func copyClip(_ clip: Clip) {
        guard let clipVM else { return }
        copiedClipID = clip.id
        clipVM.copyForPaste(clip, surface: "launcher")
        Task {
            try? await Task.sleep(for: .milliseconds(420))
            dismiss()
        }
    }

    func copyClipAsPlainText(_ clip: Clip) {
        guard let clipVM, clip.supportsPlainTextCopy else { return }
        copiedClipID = clip.id
        clipVM.copyToPasteboardAsPlainText(clip, surface: "launcher")
        Task {
            try? await Task.sleep(for: .milliseconds(420))
            dismiss()
        }
    }

    func copyUtilityResult() {
        guard let result = utilityResult, !result.copyText.isEmpty, !utilityIsLoading, let clipVM else { return }
        AnalyticsService.logUtilityResultCopied(kind: result.kind.rawValue)
        clipVM.copyPlainTextSuppressingCapture(result.copyText)
        Task {
            try? await Task.sleep(for: .milliseconds(420))
            dismiss()
        }
    }

    func launchApp(_ app: AppInfo) {
        AnalyticsService.logAppLaunchedFromLauncher(
            bundleID: app.bundleIdentifier,
            appName: app.name
        )
        if let bid = app.bundleIdentifier {
            Task { await engine.recordUsage(bundleID: bid) }
        }

        // Already-running apps activate instantly; skip the spinner to avoid
        // a one-frame flash before the dismiss animation starts.
        if isAppAlreadyRunning(app) {
            NSWorkspace.shared.open(app.bundleURL)
            onLaunch?()
            return
        }

        launchingAppID = app.id
        Task { @MainActor in
            let config = NSWorkspace.OpenConfiguration()
            config.activates = true
            _ = try? await NSWorkspace.shared.openApplication(at: app.bundleURL, configuration: config)
            // The user may have launched a different app or dismissed the
            // launcher while we were waiting; only dismiss if this is still
            // the active launch.
            guard launchingAppID == app.id else { return }
            launchingAppID = nil
            onLaunch?()
        }
    }

    private func isAppAlreadyRunning(_ app: AppInfo) -> Bool {
        guard let bid = app.bundleIdentifier else { return false }
        return !NSRunningApplication.runningApplications(withBundleIdentifier: bid).isEmpty
    }

    /// Records a system-wide app activation so frequency rankings stay accurate
    /// even when the user opens apps from the Dock, Finder, or other launchers.
    func recordSystemActivation(bundleID: String) {
        Task { await engine.recordUsage(bundleID: bundleID) }
    }

    func openTab(_ tab: BrowserTab) {
        AnalyticsService.logTabOpenedFromLauncher(
            tabType: tab.isSaved ? "saved" : "live",
            browser: tab.browser.rawValue,
            source: isSearching ? "search_results" : "default_list"
        )
        Task {
            await tabStore.touch(url: tab.url)
            if tab.isSaved {
                await tabEngine.openURL(tab.url, in: tab.browser)
            } else {
                await tabEngine.focusTab(tab)
            }
        }
        onLaunch?()
    }

    private func activateMixedSearchItem(at index: Int) {
        guard mixedSearchResults.indices.contains(index) else { return }
        switch mixedSearchResults[index] {
        case .app(let app):     launchApp(app)
        case .tab(let tab):     openTab(tab)
        }
    }

    private static func interleaveAppsAndTabs(apps: [AppInfo], tabs: [BrowserTab]) -> [LauncherSearchItem] {
        var items: [LauncherSearchItem] = []
        items.reserveCapacity(apps.count + tabs.count)
        var appIndex = 0
        var tabIndex = 0
        while appIndex < apps.count || tabIndex < tabs.count {
            if appIndex < apps.count {
                items.append(.app(apps[appIndex]))
                appIndex += 1
            }
            if tabIndex < tabs.count {
                items.append(.tab(tabs[tabIndex]))
                tabIndex += 1
            }
        }
        return items
    }

    func dismiss() { onDismiss?() }

    func openDashboard() {
        AnalyticsService.logDashboardOpened(source: "launcher_button", section: "main")
        onOpenDashboard?()
    }

    private func trackUtilityResult(_ result: UtilityResult?) {
        guard let result else { return }
        AnalyticsService.logUtilityResultShown(kind: result.kind.rawValue)
    }

    func expand() {
        tabPollerTask?.cancel()
        tabPollerTask = Task { [weak self] in
            guard let self else { return }
            tabsAreLoading = true
            await preloadSavedTabs()
            await refreshTabs()
            tabsAreLoading = false
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3))
                guard !Task.isCancelled else { return }
                await refreshTabs()
            }
        }
    }

    func reset() {
        tabPollerTask?.cancel()
        tabPollerTask     = nil
        searchQuery       = ""
        selectedIndex     = 0
        clipSelectedIndex = 0
        activePanel       = .apps
        isVisible         = false
        isExpanded        = false
        copiedClipID          = nil
        launchingAppID        = nil
        utilityResolveTask?.cancel()
        utilityResolveTask    = nil
        utilityResult         = nil
        utilityIsLoading      = false
        utilityError          = nil
        ignoreHover           = true
        tabsAreLoading        = false
        if isInstantSearchOpen {
            isInstantSearchOpen = false
            onInstantSearchChanged?(false)
        }
        instantSearchSession.reset()
        if results.isEmpty {
            Task {
                await refreshDefaults()
                instantSearchFirst = !(await InstantSearchUsageStore.shared.prefersGoogleOverInstant)
            }
        } else {
            Task {
                instantSearchFirst = !(await InstantSearchUsageStore.shared.prefersGoogleOverInstant)
            }
        }
    }
}
