import Foundation
import AppKit

actor AppSearchEngine {
    private(set) var allApps: [AppInfo] = []
    private var usageCounts: [String: Int] = [:]

    private static let usageKey = "echo_launcher_usage"

    /// Directories scanned for `.app` bundles and watched for installs/uninstalls.
    static var applicationDirectoryPaths: [String] {
        let fm = FileManager.default
        var roots: [String] = [
            "/System/Applications",
            "/System/Applications/Utilities",
            // Safari ships from a System Cryptex on modern macOS; `/Applications/Safari.app`
            // is a symlink to here, and `FileManager.enumerator(at:)` does not yield
            // symlinks, so we have to scan the Cryptex root directly.
            "/System/Cryptexes/App/System/Applications",
        ]
        roots += fm.urls(for: .applicationDirectory, in: .localDomainMask).map(\.path)
        roots += fm.urls(for: .applicationDirectory, in: .userDomainMask).map(\.path)

        // System utilities not in /Applications
        roots += [
            "/System/Library/CoreServices",
            "/System/Library/CoreServices/Applications",
        ]

        // Developer tools nested inside Xcode (Simulator, Instruments, etc.)
        for xcodeName in ["Xcode.app", "Xcode-beta.app"] {
            let devApps = "/Applications/\(xcodeName)/Contents/Developer/Applications"
            if fm.fileExists(atPath: devApps) { roots.append(devApps) }
        }

        return roots
    }

    // Background process suffixes that are never user-launchable.
    private static let blockedSuffixes: Set<String> = [
        "agent", "helper", "daemon", "updater", "spawner", "installer"
    ]

    /// Apple’s **Apps** (iOS apps on Mac) — keep below everyday apps in the launcher.
    private static let deprioritizedLauncherBundleIDs: Set<String> = [
        "com.apple.Apps",
    ]

    private func isDeprioritizedLauncherApp(_ app: AppInfo) -> Bool {
        if let id = app.bundleIdentifier, Self.deprioritizedLauncherBundleIDs.contains(id) {
            return true
        }
        // Fallback if bundle plist is missing / odd build.
        return app.bundleURL.path == "/System/Applications/Apps.app"
    }

    // MARK: - Indexing

    func indexApps() {
        usageCounts = (UserDefaults.standard.dictionary(forKey: Self.usageKey) as? [String: Int]) ?? [:]

        let fm = FileManager.default
        var seen = Set<String>()
        var apps: [AppInfo] = []

        for root in Self.applicationDirectoryPaths {
            let dir = URL(fileURLWithPath: root)
            guard let enumerator = fm.enumerator(
                at: dir,
                includingPropertiesForKeys: [.isDirectoryKey, .isPackageKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { continue }

            for case let url as URL in enumerator {
                guard url.pathExtension.lowercased() == "app" else { continue }
                let path = url.path
                guard !seen.contains(path) else { continue }
                seen.insert(path)

                let name     = url.deletingPathExtension().lastPathComponent
                guard isUserFacingApp(name: name) else { continue }
                let bundleID = Bundle(url: url)?.bundleIdentifier
                apps.append(AppInfo(
                    id: UUID(),
                    name: name,
                    bundleURL: url,
                    bundleIdentifier: bundleID,
                    usageCount: usageCounts[bundleID ?? ""] ?? 0
                ))
            }
        }

        allApps = apps.sorted { $0.name.lowercased() < $1.name.lowercased() }
    }

    private func isUserFacingApp(name: String) -> Bool {
        guard name.count >= 2 else { return false }
        let words = name.lowercased()
            .components(separatedBy: CharacterSet(charactersIn: " -_"))
            .filter { !$0.isEmpty }
        if let last = words.last, Self.blockedSuffixes.contains(last) { return false }
        return true
    }

    // MARK: - Search

    func search(query: String) -> [AppInfo] {
        if query.isEmpty {
            return Array(
                allApps
                    .sorted { lhs, rhs in
                        let lu = usageCounts[lhs.bundleIdentifier ?? ""] ?? 0
                        let ru = usageCounts[rhs.bundleIdentifier ?? ""] ?? 0
                        if lu != ru { return lu > ru }
                        let ldep = isDeprioritizedLauncherApp(lhs)
                        let rdep = isDeprioritizedLauncherApp(rhs)
                        if ldep != rdep { return !ldep }
                        return lhs.name.lowercased() < rhs.name.lowercased()
                    }
                    .prefix(4)
            )
        }

        let q = query.lowercased().filter { !$0.isWhitespace }
        let scored: [(AppInfo, Int)] = allApps.compactMap { app in
            guard let score = nameScore(query: q, name: app.name.lowercased()) else { return nil }
            let uses = usageCounts[app.bundleIdentifier ?? ""] ?? 0
            // Linear boost: each launch adds 1 000 pts — strong enough that 2 uses of a
            // subsequence-match (2 500) beats a never-opened substring-match (2 000), and
            // 5 uses of a subsequence-match (5 500) beats a never-opened prefix-match (5 000).
            let usageBoost          = uses * 1_000
            let deprioritizePenalty = isDeprioritizedLauncherApp(app) ? 15_000 : 0
            return (app, score + usageBoost - deprioritizePenalty)
        }
        return scored
            .sorted { lhs, rhs in
                if lhs.1 != rhs.1 { return lhs.1 > rhs.1 }
                return lhs.0.name.lowercased() < rhs.0.name.lowercased()
            }
            .prefix(5)
            .map(\.0)
    }

    func recordUsage(bundleID: String) {
        guard !bundleID.isEmpty else { return }
        usageCounts[bundleID, default: 0] += 1
        UserDefaults.standard.set(usageCounts, forKey: Self.usageKey)
    }

    // MARK: - Scoring
    // Base tiers (space-stripped, lowercased). Usage adds 1 000 per launch on top,
    // so the ordering within each non-exact tier flips once the app has been used:
    //   100 000  exact match          — always wins regardless of usage
    //     5 000  name starts with query
    //     2 000  name contains query as substring
    //       500  query is a subsequence of name (chars appear in order)

    private func nameScore(query: String, name: String) -> Int? {
        let q = query.filter { !$0.isWhitespace }
        let n = name.lowercased().filter { !$0.isWhitespace }

        if n == q                  { return 100_000 }
        if n.hasPrefix(q)          { return   5_000 }
        if n.contains(q)           { return   2_000 }
        if isSubsequence(q, in: n) { return     500 }
        return nil
    }

    private func isSubsequence(_ query: String, in text: String) -> Bool {
        var qi = query.startIndex
        for ch in text {
            guard qi < query.endIndex else { break }
            if ch == query[qi] { qi = query.index(after: qi) }
        }
        return qi == query.endIndex
    }
}
