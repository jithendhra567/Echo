import Foundation

enum CurrencyConversionEngine: Sendable {

    nonisolated static func makeResult(query: CurrencyQuery, rate: Double, stale: Bool = false) -> UtilityResult {
        let converted = query.amount * rate
        let preview = format(amount: converted, code: query.toCode)
        let copy = preview
        let detail = "1 \(query.fromCode) = \(formatRate(rate)) \(query.toCode)"
            + (stale ? " · cached" : "")
        return UtilityResult(
            kind: .currency,
            copyText: copy,
            previewText: preview,
            detailText: detail
        )
    }

    nonisolated static func loadingPlaceholder(query: CurrencyQuery) -> UtilityResult {
        UtilityResult(
            kind: .currency,
            copyText: "",
            previewText: "Fetching rates…",
            detailText: "\(format(amount: query.amount, code: query.fromCode)) → \(query.toCode)"
        )
    }

    nonisolated static func offlineFallback(query: CurrencyQuery, entry: CurrencyCacheEntry) -> UtilityResult {
        makeResult(query: query, rate: entry.rate, stale: true)
    }

    private nonisolated static func format(amount: Double, code: String) -> String {
        let n = CalculationEngine.formatNumber(amount)
        return "\(n) \(code)"
    }

    private nonisolated static func formatRate(_ rate: Double) -> String {
        CalculationEngine.formatNumber(rate)
    }
}
