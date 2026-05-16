import Foundation
import os

actor CurrencyRateCacheManager {

    static let shared = CurrencyRateCacheManager()

    private let log = Logger(subsystem: "com.echo", category: "CurrencyCacheManager")

    private init() {}

    // MARK: - Public

    func applyInactivityPolicyIfNeeded() {
        var snap = CurrencyCacheStore.snapshot()
        guard let last = snap.lastCurrencyActivityAt else { return }
        if Date().timeIntervalSince(last) > CurrencyCachePolicy.inactivityCleanup {
            log.info("Currency cache expired after 3 days inactivity — clearing")
            CurrencyCacheStore.clear()
        }
    }

    func touchCurrencyActivity() {
        var snap = CurrencyCacheStore.snapshot()
        snap.lastCurrencyActivityAt = Date()
        CurrencyCacheStore.save(snap)
    }

    func cachedRate(base: String, target: String) -> CurrencyCacheEntry? {
        let key = CurrencyCacheEntry.key(base: base, target: target)
        var snap = CurrencyCacheStore.snapshot()
        guard var entry = snap.entries[key] else { return nil }
        entry.lastUsed = Date()
        snap.entries[key] = entry
        CurrencyCacheStore.save(snap)
        return entry
    }

    func isStale(_ entry: CurrencyCacheEntry) -> Bool {
        Date().timeIntervalSince(entry.fetchedAt) > CurrencyCachePolicy.refreshInterval
    }

    func shouldRefresh(base: String, target: String) -> Bool {
        guard let entry = CurrencyCacheStore.snapshot().entries[CurrencyCacheEntry.key(base: base, target: target)] else {
            return true
        }
        return isStale(entry)
    }

  /// Returns cached rate if present; fetches from API when missing.
    func rate(
        base: String,
        target: String,
        forceRefresh: Bool = false
    ) async throws -> CurrencyCacheEntry {
        applyInactivityPolicyIfNeeded()
        touchCurrencyActivity()

        let b = base.uppercased()
        let t = target.uppercased()
        let key = CurrencyCacheEntry.key(base: b, target: t)

        if !forceRefresh, let existing = CurrencyCacheStore.snapshot().entries[key] {
            _ = cachedRate(base: b, target: t)
            log.debug("Cache hit \(key, privacy: .public)")
            return existing
        }

        log.info("Cache miss — fetching \(key, privacy: .public)")
        try await fetchAndMerge(base: b, targets: [t])

        guard let entry = CurrencyCacheStore.snapshot().entries[key] else {
            throw FrankfurterAPIClient.ClientError.decodeFailed
        }
        return entry
    }

    /// Background refresh when stale but still within activity window.
    func refreshIfStale(base: String, target: String) async {
        applyInactivityPolicyIfNeeded()
        guard shouldRefresh(base: base, target: target) else { return }
        guard CurrencyCacheStore.snapshot().lastCurrencyActivityAt != nil else { return }

        let b = base.uppercased()
        let t = target.uppercased()
        log.info("Background refresh \(b, privacy: .public)→\(t, privacy: .public)")
        do {
            try await fetchAndMerge(base: b, targets: [t])
        } catch {
            log.error("Background refresh failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Fetch

    private func fetchAndMerge(base: String, targets: [String]) async throws {
        let response = try await FrankfurterAPIClient.fetchLatest(base: base, targets: targets)
        let now = Date()
        var snap = CurrencyCacheStore.snapshot()
        snap.lastCurrencyActivityAt = now

        for (code, rate) in response.rates {
            let key = CurrencyCacheEntry.key(base: response.base, target: code)
            let previous = snap.entries[key]
            snap.entries[key] = CurrencyCacheEntry(
                base: response.base.uppercased(),
                target: code.uppercased(),
                rate: rate,
                fetchedAt: now,
                lastUsed: previous?.lastUsed ?? now
            )
        }

        CurrencyCacheStore.save(snap)
        log.info("Cached \(response.rates.count) rates for base \(response.base, privacy: .public)")
    }
}
