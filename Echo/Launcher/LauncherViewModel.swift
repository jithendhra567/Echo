import AppKit
import Observation

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
    var ignoreHover: Bool = true

    var onDismiss: (() -> Void)?
    var onLaunch:  (() -> Void)?

    var clipVM: ClipViewModel?

    private let engine    = AppSearchEngine()
    private let tabEngine = BrowserTabEngine()

    enum ActivePanel { case apps, clipboard }

    // MARK: - Derived

    var filteredClips: [Clip] {
        guard let clipVM else { return [] }
        let query = searchQuery.lowercased()
        guard !query.isEmpty else { return Array(clipVM.clips.prefix(10)) }
        return clipVM.clips.filter { clipMatches($0, query: query) }
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

    var combinedCount: Int {
        (showsGoogleFallback ? 1 : results.count) + tabResults.count
    }

    init() {
        Task {
            await engine.indexApps()
            await refreshDefaults()
        }
    }

    // MARK: - Search

    func search() {
        selectedIndex     = 0
        clipSelectedIndex = 0
        // App results update immediately (fast); tab results update when AppleScript finishes.
        Task { results    = await engine.search(query: searchQuery) }
        Task {
            let all = await tabEngine.fetchTabs()
            tabResults = tabEngine.search(query: searchQuery, in: all)
        }
    }

    func refreshDefaults() async {
        results = await engine.search(query: "")
    }

    func refreshTabs() async {
        let all = await tabEngine.fetchTabs()
        tabResults = tabEngine.search(query: searchQuery, in: all)
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

    // MARK: - Actions

    func searchGoogle() {
        guard !searchQuery.isEmpty,
              let encoded = searchQuery.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://www.google.com/search?q=\(encoded)")
        else { return }
        NSWorkspace.shared.open(url)
        onLaunch?()
    }

    func confirmSelected() {
        switch activePanel {
        case .apps:
            let appCount = showsGoogleFallback ? 1 : results.count
            if selectedIndex < appCount {
                if showsGoogleFallback { searchGoogle(); return }
                guard results.indices.contains(selectedIndex) else { return }
                launchApp(results[selectedIndex])
            } else {
                let tabIdx = selectedIndex - appCount
                guard tabResults.indices.contains(tabIdx) else { return }
                openTab(tabResults[tabIdx])
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
        clipVM.copy(clip)
        Task {
            try? await Task.sleep(for: .milliseconds(420))
            dismiss()
        }
    }

    func launchApp(_ app: AppInfo) {
        NSWorkspace.shared.open(app.bundleURL)
        if let bid = app.bundleIdentifier {
            Task { await engine.recordUsage(bundleID: bid) }
        }
        onLaunch?()
    }

    func openTab(_ tab: BrowserTab) {
        guard let url = URL(string: tab.url) else { return }
        NSWorkspace.shared.open(url)
        onLaunch?()
    }

    func dismiss() { onDismiss?() }

    func expand() {
        Task { await refreshTabs() }
    }

    func reset() {
        searchQuery       = ""
        selectedIndex     = 0
        clipSelectedIndex = 0
        activePanel       = .apps
        isVisible         = false
        isExpanded        = false
        copiedClipID      = nil
        ignoreHover       = true
        Task { await refreshDefaults() }
    }
}
