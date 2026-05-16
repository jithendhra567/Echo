import Foundation
import os

enum CurrencyConversionError: Error, LocalizedError {
    case cancelled

    var errorDescription: String? {
        switch self {
        case .cancelled: return nil
        }
    }
}

actor CurrencyConversionService {

    static let shared = CurrencyConversionService()

    private let log = Logger(subsystem: "com.echo", category: "CurrencyConversion")
    private let cache = CurrencyRateCacheManager.shared

    private init() {}

    /// Synchronous read from on-disk cache (for instant UI).
    nonisolated func peekCached(query: CurrencyQuery) -> UtilityResult? {
        let key = CurrencyCacheEntry.key(base: query.fromCode, target: query.toCode)
        let snap = CurrencyCacheStore.snapshot()
        guard let entry = snap.entries[key] else { return nil }
        let stale = Date().timeIntervalSince(entry.fetchedAt) > CurrencyCachePolicy.refreshInterval
        return CurrencyConversionEngine.makeResult(query: query, rate: entry.rate, stale: stale)
    }

    /// Converts using cache-first strategy; fetches on miss.
    func convert(_ query: CurrencyQuery) async throws -> UtilityResult {
        log.info("Convert \(query.amount) \(query.fromCode, privacy: .public)→\(query.toCode, privacy: .public)")

        if let peek = peekCached(query: query) {
            Task { await cache.refreshIfStale(base: query.fromCode, target: query.toCode) }
            return peek
        }

        let entry = try await cache.rate(base: query.fromCode, target: query.toCode)
        return CurrencyConversionEngine.makeResult(query: query, rate: entry.rate)
    }

    func refreshIfStale(base: String, target: String) async {
        await cache.refreshIfStale(base: base, target: target)
    }
}
