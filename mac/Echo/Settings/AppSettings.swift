import Foundation
import Observation

/// App-wide, UserDefaults-backed settings.
///
/// The `@Observable` instance drives the Dashboard UI on the main actor.
/// SQLite actors (`ClipStore`, `BrowserTabStore`) and other nonisolated code
/// read the same values through the `nonisolated static` accessors —
/// `UserDefaults` is thread-safe, so both sides always agree.
@Observable
@MainActor
final class AppSettings {

    // MARK: - Keys

    nonisolated static let retentionDaysKey       = "echo_retention_days"
    nonisolated static let ignoredWebsitesKey     = "echo_ignored_websites"
    nonisolated static let ignoredAppsKey         = "echo_ignored_apps"
    nonisolated static let clipboardPausedKey     = "echo_clipboard_paused"
    nonisolated static let captureImagesKey       = "echo_capture_images"
    nonisolated static let skipConcealedKey       = "echo_skip_concealed"

    nonisolated static let defaultRetentionDays = 30
    static let retentionChoices = [7, 14, 30, 60, 90, 180, 365]

    // MARK: - Stored settings

    /// Unpinned clips older than this many days are pruned from history.
    var retentionDays: Int {
        didSet { UserDefaults.standard.set(retentionDays, forKey: Self.retentionDaysKey) }
    }

    /// Domains excluded from saving: URL clips and browser-tab history matching
    /// these (including subdomains) are never persisted.
    var ignoredWebsites: [String] {
        didSet { UserDefaults.standard.set(ignoredWebsites, forKey: Self.ignoredWebsitesKey) }
    }

    /// Bundle IDs of apps whose copies are never captured (e.g. password managers).
    var ignoredApps: [String] {
        didSet { UserDefaults.standard.set(ignoredApps, forKey: Self.ignoredAppsKey) }
    }

    /// Temporarily stop recording clipboard changes.
    var isClipboardPaused: Bool {
        didSet { UserDefaults.standard.set(isClipboardPaused, forKey: Self.clipboardPausedKey) }
    }

    /// Capture copied images (can be turned off to save space).
    var captureImages: Bool {
        didSet { UserDefaults.standard.set(captureImages, forKey: Self.captureImagesKey) }
    }

    /// Skip pasteboard content flagged as concealed/transient
    /// (passwords from 1Password, Keychain, etc.).
    var skipConcealedContent: Bool {
        didSet { UserDefaults.standard.set(skipConcealedContent, forKey: Self.skipConcealedKey) }
    }

    init() {
        let d = UserDefaults.standard
        let storedDays = d.integer(forKey: Self.retentionDaysKey)
        retentionDays        = storedDays > 0 ? storedDays : Self.defaultRetentionDays
        ignoredWebsites      = d.stringArray(forKey: Self.ignoredWebsitesKey) ?? []
        ignoredApps          = d.stringArray(forKey: Self.ignoredAppsKey) ?? []
        isClipboardPaused    = d.bool(forKey: Self.clipboardPausedKey)
        captureImages        = d.object(forKey: Self.captureImagesKey) == nil
                               ? true : d.bool(forKey: Self.captureImagesKey)
        skipConcealedContent = d.object(forKey: Self.skipConcealedKey) == nil
                               ? true : d.bool(forKey: Self.skipConcealedKey)
    }

    // MARK: - Ignored websites

    /// Adds a website (accepts full URLs or bare domains). Returns the
    /// normalized domain, or nil if the input wasn't a valid domain.
    @discardableResult
    func addIgnoredWebsite(_ raw: String) -> String? {
        guard let domain = Self.normalizeDomain(raw) else { return nil }
        guard !ignoredWebsites.contains(domain) else { return domain }
        ignoredWebsites.append(domain)
        ignoredWebsites.sort()
        return domain
    }

    func removeIgnoredWebsite(_ domain: String) {
        ignoredWebsites.removeAll { $0 == domain }
    }

    // MARK: - Ignored apps

    func addIgnoredApp(bundleID: String) {
        let id = bundleID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty, !ignoredApps.contains(id) else { return }
        ignoredApps.append(id)
        ignoredApps.sort()
    }

    func removeIgnoredApp(bundleID: String) {
        ignoredApps.removeAll { $0 == bundleID }
    }

    // MARK: - Nonisolated readers (safe from any actor)

    nonisolated static var storedRetentionDays: Int {
        let v = UserDefaults.standard.integer(forKey: retentionDaysKey)
        return v > 0 ? v : defaultRetentionDays
    }

    nonisolated static var storedRetentionTTL: TimeInterval {
        TimeInterval(storedRetentionDays) * 24 * 3600
    }

    nonisolated static var storedIgnoredWebsites: [String] {
        UserDefaults.standard.stringArray(forKey: ignoredWebsitesKey) ?? []
    }

    nonisolated static var storedIgnoredApps: [String] {
        UserDefaults.standard.stringArray(forKey: ignoredAppsKey) ?? []
    }

    /// True when the URL's host matches an ignored domain (or a subdomain of one).
    nonisolated static func isWebsiteIgnored(_ urlString: String) -> Bool {
        guard let host = host(of: urlString) else { return false }
        return isHostIgnored(host)
    }

    nonisolated static func isHostIgnored(_ rawHost: String) -> Bool {
        var host = rawHost.lowercased()
        if host.hasPrefix("www.") { host.removeFirst(4) }
        for domain in storedIgnoredWebsites {
            if host == domain || host.hasSuffix("." + domain) { return true }
        }
        return false
    }

    // MARK: - Domain helpers

    /// Extracts a lowercase host from a URL string ("https://a.b.com/x" → "a.b.com").
    nonisolated static func host(of urlString: String) -> String? {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: trimmed), let host = url.host, !host.isEmpty {
            return host.lowercased()
        }
        // Bare domains without a scheme ("news.ycombinator.com/item?id=1")
        var s = trimmed.lowercased()
        for scheme in ["https://", "http://"] where s.hasPrefix(scheme) {
            s.removeFirst(scheme.count)
        }
        s = s.components(separatedBy: "/").first ?? s
        s = s.components(separatedBy: ":").first ?? s
        guard s.contains("."), !s.contains(" "), !s.isEmpty else { return nil }
        return s
    }

    /// Normalizes user input into a canonical domain:
    /// strips scheme, path, port, and a leading "www.".
    nonisolated static func normalizeDomain(_ raw: String) -> String? {
        guard var domain = host(of: raw) else { return nil }
        if domain.hasPrefix("www.") { domain.removeFirst(4) }
        guard domain.contains(".") else { return nil }
        return domain
    }
}
