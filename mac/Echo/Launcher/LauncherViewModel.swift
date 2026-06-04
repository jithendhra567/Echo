import AppKit
import Observation

@Observable
@MainActor
final class LauncherViewModel {
    var searchQuery: String = ""
    var results: [AppInfo] = []
    var tabResults: [BrowserTab] = []
    var windowResults: [AppWindow] = []
    var isLoadingWindows: Bool = false
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

    let instantSearchSession = InstantSearchSession()

    private var utilityResolveTask: Task<Void, Never>?

    var onDismiss: (() -> Void)?
    var onLaunch:  (() -> Void)?
    var onInstantSearchChanged: ((Bool) -> Void)?

    var clipVM: ClipViewModel?

    private let engine        = AppSearchEngine()
    private let tabEngine     = BrowserTabEngine()
    private let windowEngine  = AppWindowEngine()
    private let tabStore      = BrowserTabStore()

    private var cachedAllTabs: [BrowserTab] = []
    private var cachedAllWindows: [AppWindow] = []
    private var tabPollerTask: Task<Void, Never>?
    private var windowFetchTask: Task<Void, Never>?
    private var expandSessionID = UUID()
    private var launcherOpenedAt: Date?
    private var appIndexWatcher: AppIndexWatcher?

    private static let windowFetchDebounceMs: UInt64 = 280
    /// Wait for open animation before any AX / window work.
    private static let windowFetchAfterOpenMs: UInt64 = 700
    private static let tabPollDelayMs: UInt64 = 2_500

    enum ActivePanel { case apps, clipboard }

    // MARK: - Derived

    var filteredClips: [Clip] {
        guard let clipVM else { return [] }
        let query = searchQuery.lowercased()
        guard !query.isEmpty else { return Array(clipVM.clips.prefix(50)) }
        return clipVM.clips.filter { clipMatches($0, query: query) }
    }

    private func clipMatches(_ clip: Clip, query: String) -> Bool {
        if clip.plainText?.lowercased().contains(query) == true { return true }
        if clip.attributedString?.string.lowercased().contains(query) == true { return true }
        if clip.sourceAppName?.lowercased().contains(query) == true { return true }
        if clip.windowTitle?.lowercased().contains(query) == true { return true }
        return false
    }

    var canSearchWindows: Bool { AccessibilityPermission.isGranted }

    var showsGoogleFallback: Bool {
        !searchQuery.isEmpty && results.isEmpty && windowResults.isEmpty && tabResults.isEmpty && !isLoadingWindows
    }

    /// Apps interleaved with open windows; title-only matches appear as standalone rows with app icons.
    var appsListItems: [LauncherAppsListItem] {
        guard !showsGoogleFallback else { return [] }
        let query = AppWindowEngine.normalizedQuery(searchQuery)
        var items: [LauncherAppsListItem] = []
        var shownWindowIDs = Set<UUID>()

        for (index, app) in results.enumerated() {
            items.append(.app(app))
            let appWindows = windows(for: app)
            if index == 0, isLoadingWindows, appWindows.isEmpty {
                items.append(.windowsLoading(appID: app.id))
            }
            if appWindows.count > 1 {
                for window in appWindows {
                    items.append(.window(window, nested: true))
                    shownWindowIDs.insert(window.id)
                }
            } else {
                for window in appWindows {
                    shownWindowIDs.insert(window.id)
                }
            }
        }

        if !query.isEmpty {
            for window in windowResults where !shownWindowIDs.contains(window.id) {
                guard AppWindowEngine.normalizedQuery(window.title).contains(query) else { continue }
                items.append(.window(window, nested: false))
                shownWindowIDs.insert(window.id)
            }
        }

        if isLoadingWindows, items.isEmpty, !query.isEmpty {
            items.append(.windowsLoading(appID: UUID()))
        }

        return items
    }

    func windows(for app: AppInfo) -> [AppWindow] {
        let bundleID = app.bundleIdentifier
        let normalizedName = AppWindowEngine.normalizedQuery(app.name)
        return windowResults.filter { window in
            if let bundleID, let windowBundle = window.bundleIdentifier, bundleID == windowBundle {
                return true
            }
            let windowName = AppWindowEngine.normalizedQuery(window.appName)
            return windowName == normalizedName
                || windowName.contains(normalizedName)
                || normalizedName.contains(windowName)
        }
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

    var combinedCount: Int {
        utilityRowCount
            + (showsGoogleFallback ? webFallbackRowCount : appsListItems.count)
            + tabResults.count
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
        tabResults = tabEngine.search(query: searchQuery, in: cachedAllTabs)
        if !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            scheduleTabPollerIfNeeded()
        }
        Task {
            results = await engine.search(query: searchQuery)
            instantSearchFirst = !(await InstantSearchUsageStore.shared.prefersGoogleOverInstant)
            scheduleWindowFetch()
        }
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
            } catch {
                guard !Task.isCancelled else { return }
                utilityIsLoading = false
                if let fallback = service.peekCached(query: query) {
                    utilityError = "Offline — showing cached rate"
                    utilityResult = fallback
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

        cachedAllTabs = activeTabs + savedOnly
        tabResults    = tabEngine.search(query: searchQuery, in: cachedAllTabs)
    }

    private func scheduleWindowFetch() {
        windowFetchTask?.cancel()
        let query = searchQuery
        let sessionID = expandSessionID

        guard canSearchWindows else {
            isLoadingWindows = false
            windowResults = []
            cachedAllWindows = []
            return
        }

        if results.isEmpty, query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            isLoadingWindows = false
            return
        }

        if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            windowResults = []
        }
        windowFetchTask = Task {
            let openedRecently = launcherOpenedAt.map { Date().timeIntervalSince($0) < 0.8 } ?? false
            if openedRecently {
                try? await Task.sleep(for: .milliseconds(Self.windowFetchAfterOpenMs))
            }
            guard !Task.isCancelled, sessionID == expandSessionID, query == searchQuery else { return }
            let debounceMs = query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? 0
                : Self.windowFetchDebounceMs
            if debounceMs > 0 {
                try? await Task.sleep(for: .milliseconds(debounceMs))
            }
            guard !Task.isCancelled, sessionID == expandSessionID, query == searchQuery else { return }
            isLoadingWindows = true
            await fetchWindowsForQuery(query)
        }
    }

    private func fetchWindowsForQuery(_ query: String) async {
        defer {
            if query == searchQuery {
                isLoadingWindows = false
            }
        }
        guard canSearchWindows, query == searchQuery, !Task.isCancelled else { return }

        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let appResults = trimmed.isEmpty ? results : await engine.search(query: query)
        if !trimmed.isEmpty {
            guard query == searchQuery, !Task.isCancelled else { return }
            results = appResults
        }

        let bundleIDs = Set(appResults.compactMap(\.bundleIdentifier))
        let appNames = Set(appResults.map(\.name))

        let targets: [RunningAppSnapshot]
        if trimmed.isEmpty, let first = appResults.first {
            targets = AppWindowEngine.runningApps(for: first)
        } else {
            var matched = AppWindowEngine.runningApps(
                matching: query,
                bundleIDs: bundleIDs,
                appNames: appNames
            )
            if matched.isEmpty {
                matched = appResults.flatMap { AppWindowEngine.runningApps(for: $0) }
            }
            targets = matched
        }

        let windows: [AppWindow]
        if trimmed.isEmpty {
            if targets.isEmpty {
                windows = []
            } else {
                windows = await windowEngine.fetchWindows(runningApps: targets)
            }
        } else {
            let allRunning = AppWindowEngine.snapshotRunningApps()
            async let appWindows: [AppWindow] = targets.isEmpty
                ? []
                : windowEngine.fetchWindows(runningApps: targets)
            async let titleWindows: [AppWindow] = windowEngine.fetchWindowsMatchingTitle(
                query,
                runningApps: allRunning
            )
            windows = AppWindowEngine.merged(await appWindows, await titleWindows)
        }
        guard query == searchQuery, !Task.isCancelled else { return }

        cachedAllWindows = windows
        if trimmed.isEmpty {
            windowResults = windows
        } else {
            windowResults = windowEngine.search(
                query: query,
                in: windows,
                bundleIDs: bundleIDs,
                appNames: appNames
            )
        }
    }

    private func scheduleTabPollerIfNeeded() {
        guard tabPollerTask == nil else { return }
        tabPollerTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(Self.tabPollDelayMs))
            guard !Task.isCancelled else { return }
            await self?.refreshTabs()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled else { break }
                await self?.refreshTabs()
            }
        }
    }

    // MARK: - Panel switching

    func switchPanel() {
        activePanel = (activePanel == .apps) ? .clipboard : .apps
        if activePanel == .clipboard { clipSelectedIndex = 0 }
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
        guard !searchQuery.isEmpty,
              let encoded = searchQuery.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://www.google.com/search?q=\(encoded)")
        else { return }
        NSWorkspace.shared.open(url)
        onLaunch?()
    }

    func openInstantSearch() {
        guard let url = instantSearchTargetURL else { return }
        instantSearchSession.load(url)
        isInstantSearchOpen = true
        onInstantSearchChanged?(true)
        let host = url.host ?? ""
        Task { await InstantSearchUsageStore.shared.recordInstantOpen(host: host) }
    }

    func closeInstantSearch() {
        guard isInstantSearchOpen else { return }
        isInstantSearchOpen = false
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
            guard contentIndex < appsListItems.count else {
                let tabIdx = contentIndex - appsListItems.count
                guard tabResults.indices.contains(tabIdx) else { return }
                openTab(tabResults[tabIdx])
                return
            }
            switch appsListItems[contentIndex] {
            case .app(let app):
                launchApp(app)
            case .window(let window, _):
                focusWindow(window)
            case .windowsLoading:
                break
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
        clipVM.copyToPasteboard(clip)
        Task {
            try? await Task.sleep(for: .milliseconds(420))
            dismiss()
        }
    }

    func copyClipAsPlainText(_ clip: Clip) {
        guard let clipVM, clip.supportsPlainTextCopy else { return }
        copiedClipID = clip.id
        clipVM.copyToPasteboardAsPlainText(clip)
        Task {
            try? await Task.sleep(for: .milliseconds(420))
            dismiss()
        }
    }

    func copyUtilityResult() {
        guard let result = utilityResult, !result.copyText.isEmpty, !utilityIsLoading, let clipVM else { return }
        clipVM.copyPlainTextSuppressingCapture(result.copyText)
        Task {
            try? await Task.sleep(for: .milliseconds(420))
            dismiss()
        }
    }

    func launchApp(_ app: AppInfo) {
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
        Task {
            await tabStore.touch(url: tab.url)
            if tab.isSaved {
                // Tab is from history (not currently open) — open a new tab.
                guard let url = URL(string: tab.url) else { return }
                NSWorkspace.shared.open(url)
            } else {
                // Tab is currently open — focus the existing tab via AppleScript.
                await tabEngine.focusTab(tab)
            }
        }
        onLaunch?()
    }

    func focusWindow(_ window: AppWindow) {
        Task { await windowEngine.focusWindow(window) }
        onLaunch?()
    }

    func dismiss() { onDismiss?() }

    func expand() {
        expandSessionID = UUID()
        launcherOpenedAt = Date()
        tabPollerTask?.cancel()
        tabPollerTask = nil

        Task {
            try? await Task.sleep(for: .milliseconds(Self.windowFetchAfterOpenMs))
            guard isExpanded, isVisible else { return }
            if results.isEmpty {
                results = await engine.search(query: "")
            }
            scheduleWindowFetch()
        }
        Task {
            try? await Task.sleep(for: .seconds(2))
            AccessibilityPermission.requestIfNeeded()
        }
    }

    /// Light reset when opening — keeps cached app list so the panel appears instantly.
    func prepareForShow() {
        utilityResolveTask?.cancel()
        utilityResolveTask = nil
        utilityResult = nil
        utilityIsLoading = false
        utilityError = nil
        windowFetchTask?.cancel()
        windowFetchTask = nil
        isLoadingWindows = false
        searchQuery = ""
        selectedIndex = 0
        clipSelectedIndex = 0
        activePanel = .apps
        copiedClipID = nil
        launchingAppID = nil
        ignoreHover = true
        isInstantSearchOpen = false
        instantSearchSession.reset()
        onInstantSearchChanged?(false)
    }

    func reset() {
        tabPollerTask?.cancel()
        tabPollerTask = nil
        launcherOpenedAt = nil
        windowResults = []
        cachedAllWindows = []
        prepareForShow()
        isVisible = false
        isExpanded = false
        Task {
            await refreshDefaults()
            instantSearchFirst = !(await InstantSearchUsageStore.shared.prefersGoogleOverInstant)
        }
    }
}
