import Foundation

/// Persists how often the user opens Instant Search vs external Google / browser.
actor InstantSearchUsageStore {
    static let shared = InstantSearchUsageStore()

    private static let instantKey = "echo_instant_search_usage"
    private static let googleKey  = "echo_google_search_usage"
    private static let hostKey      = "echo_instant_search_hosts"

    private var instantOpens: Int
    private var googleOpens: Int
    private var hostCounts: [String: Int]

    private init() {
        let defaults = UserDefaults.standard
        instantOpens = defaults.integer(forKey: Self.instantKey)
        googleOpens  = defaults.integer(forKey: Self.googleKey)
        hostCounts   = (defaults.dictionary(forKey: Self.hostKey) as? [String: Int]) ?? [:]
    }

    func recordInstantOpen(host: String) {
        instantOpens += 1
        if !host.isEmpty {
            hostCounts[host, default: 0] += 1
        }
        persist()
    }

    func recordGoogleOpen() {
        googleOpens += 1
        persist()
    }

    /// When the user prefers Google in the browser, the Google row can appear above Instant Search.
    var prefersGoogleOverInstant: Bool {
        googleOpens > instantOpens + 2
    }

    func hostUsage(_ host: String) -> Int {
        hostCounts[host] ?? 0
    }

    private func persist() {
        let defaults = UserDefaults.standard
        defaults.set(instantOpens, forKey: Self.instantKey)
        defaults.set(googleOpens,  forKey: Self.googleKey)
        defaults.set(hostCounts,  forKey: Self.hostKey)
    }
}
