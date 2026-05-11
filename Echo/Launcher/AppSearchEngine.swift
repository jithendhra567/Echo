import Foundation
import AppKit

actor AppSearchEngine {
    private(set) var allApps: [AppInfo] = []
    private var usageCounts: [String: Int] = [:]

    private static let usageKey = "echo_launcher_usage"

    private static var searchRoots: [String] {
        let fm = FileManager.default
        var roots: [String] = [
            "/System/Applications",
            "/System/Applications/Utilities",
        ]
        roots += fm.urls(for: .applicationDirectory, in: .localDomainMask).map(\.path)
        roots += fm.urls(for: .applicationDirectory, in: .userDomainMask).map(\.path)
        return roots
    }

    // Background process suffixes that are never user-launchable.
    private static let blockedSuffixes: Set<String> = [
        "agent", "helper", "daemon", "updater", "spawner", "installer"
    ]

    // MARK: - Indexing

    func indexApps() {
        usageCounts = (UserDefaults.standard.dictionary(forKey: Self.usageKey) as? [String: Int]) ?? [:]

        let fm = FileManager.default
        var seen = Set<String>()
        var apps: [AppInfo] = []

        for root in Self.searchRoots {
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
                        lhs.usageCount != rhs.usageCount
                            ? lhs.usageCount > rhs.usageCount
                            : lhs.name.lowercased() < rhs.name.lowercased()
                    }
                    .prefix(4)
            )
        }

        let q = query.lowercased().filter { !$0.isWhitespace }
        let scored: [(AppInfo, Int)] = allApps.compactMap { app in
            guard let score = nameScore(query: q, name: app.name.lowercased()) else { return nil }
            let uses = usageCounts[app.bundleIdentifier ?? ""] ?? 0
            let usageBoost = Int(log2(Double(uses) + 1) * 200)
            return (app, score + usageBoost)
        }
        return scored
            .sorted { $0.1 > $1.1 }
            .prefix(5)
            .map(\.0)
    }

    func recordUsage(bundleID: String) {
        guard !bundleID.isEmpty else { return }
        usageCounts[bundleID, default: 0] += 1
        UserDefaults.standard.set(usageCounts, forKey: Self.usageKey)
    }

    // MARK: - Scoring
    // Tiers (descending) — all comparisons are space-stripped + lowercased:
    //   10 000  exact match
    //    5 000  name starts with query
    //    2 000  name contains query as substring
    //      500  query is a subsequence of name (chars appear in order)

    private func nameScore(query: String, name: String) -> Int? {
        let q = query.filter { !$0.isWhitespace }
        let n = name.lowercased().filter { !$0.isWhitespace }

        if n == q                   { return 10_000 }
        if n.hasPrefix(q)           { return  5_000 + lengthBonus(name) }
        if n.contains(q)            { return  2_000 + lengthBonus(name) }
        if isSubsequence(q, in: n)  { return    500 + lengthBonus(name) }
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

    private func lengthBonus(_ name: String) -> Int { max(0, 80 - name.count) }
}
