import AppKit
import Observation

// MARK: - Stat models

struct WebsiteStat: Identifiable {
    let domain: String
    let count: Int
    var id: String { domain }
}

struct AppLaunchStat: Identifiable {
    let bundleID: String
    let name: String
    let icon: NSImage?
    let count: Int
    var id: String { bundleID }
}

struct SourceAppStat: Identifiable {
    let name: String
    let icon: NSImage?
    let count: Int
    var id: String { name }
}

struct DayActivityStat: Identifiable {
    let day: Date
    let count: Int
    var id: Date { day }
}

// MARK: - Provider

/// Aggregates usage data for the Dashboard's Statistics pane:
/// browser-tab history (own read connection), launcher usage counts
/// (UserDefaults), and clipboard stats derived from the loaded clips.
@Observable
@MainActor
final class StatsProvider {
    private let tabStore = BrowserTabStore()

    private(set) var topWebsites: [WebsiteStat] = []
    private(set) var topLaunchedApps: [AppLaunchStat] = []

    // MARK: - Refresh

    func refresh(clips: [Clip]) {
        refreshLaunchedApps()
        Task { await refreshWebsites(clips: clips) }
    }

    private func refreshWebsites(clips: [Clip]) async {
        var counts: [String: Int] = [:]

        for tab in await tabStore.fetchAll() {
            if let domain = Self.displayDomain(of: tab.url) {
                counts[domain, default: 0] += 1
            }
        }
        for clip in clips where clip.isLink {
            if let text = clip.plainText, let domain = Self.displayDomain(of: text) {
                counts[domain, default: 0] += 1
            }
        }

        topWebsites = counts
            .map { WebsiteStat(domain: $0.key, count: $0.value) }
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0.domain < $1.domain }
            .prefix(10)
            .map { $0 }
    }

    private func refreshLaunchedApps() {
        let usage = (UserDefaults.standard.dictionary(forKey: AppSearchEngine.usageKey) as? [String: Int]) ?? [:]
        topLaunchedApps = usage
            .sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
            .prefix(10)
            .map { bundleID, count in
                let url = NSWorkspace.shared.urlsForApplications(withBundleIdentifier: bundleID).first
                let name = url.map { $0.deletingPathExtension().lastPathComponent } ?? bundleID
                let icon = url.map { NSWorkspace.shared.icon(forFile: $0.path) }
                return AppLaunchStat(bundleID: bundleID, name: name, icon: icon, count: count)
            }
    }

    func resetLaunchStats() {
        UserDefaults.standard.removeObject(forKey: AppSearchEngine.usageKey)
        topLaunchedApps = []
    }

    /// Deletes saved browser-tab history for an ignored domain.
    func deleteWebsiteHistory(domain: String) {
        Task {
            await tabStore.deleteMatching(domain: domain)
            topWebsites.removeAll { $0.domain == domain || $0.domain.hasSuffix("." + domain) }
        }
    }

    // MARK: - Clipboard aggregations (pure, computed from loaded clips)

    static func sourceApps(from clips: [Clip], limit: Int = 8) -> [SourceAppStat] {
        var counts: [String: Int] = [:]
        var icons: [String: NSImage] = [:]
        for clip in clips {
            let name = clip.sourceAppName ?? "Unknown"
            counts[name, default: 0] += 1
            if icons[name] == nil, let icon = clip.appIcon { icons[name] = icon }
        }
        return counts
            .map { SourceAppStat(name: $0.key, icon: icons[$0.key], count: $0.value) }
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0.name < $1.name }
            .prefix(limit)
            .map { $0 }
    }

    static func dailyActivity(from clips: [Clip], days: Int = 14) -> [DayActivityStat] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        var buckets: [Date: Int] = [:]
        for offset in 0..<days {
            if let day = cal.date(byAdding: .day, value: -offset, to: today) {
                buckets[day] = 0
            }
        }
        for clip in clips {
            let day = cal.startOfDay(for: clip.createdAt)
            if buckets[day] != nil { buckets[day]! += 1 }
        }
        return buckets
            .map { DayActivityStat(day: $0.key, count: $0.value) }
            .sorted { $0.day < $1.day }
    }

    static func typeCounts(from clips: [Clip]) -> [(type: String, count: Int)] {
        var counts: [String: Int] = [:]
        for clip in clips {
            counts[clip.autoTag.rawValue, default: 0] += 1
        }
        return counts
            .map { (type: $0.key, count: $0.value) }
            .sorted { $0.count > $1.count }
    }

    // MARK: - Helpers

    /// "https://www.github.com/foo" → "github.com"
    nonisolated static func displayDomain(of urlString: String) -> String? {
        guard var host = AppSettings.host(of: urlString) else { return nil }
        if host.hasPrefix("www.") { host.removeFirst(4) }
        return host.isEmpty ? nil : host
    }
}
