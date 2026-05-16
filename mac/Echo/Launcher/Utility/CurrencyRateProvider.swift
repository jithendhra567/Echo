import Foundation

/// Legacy protocol — live rates use `CurrencyConversionService`.
protocol CurrencyRateProvider: Sendable {
    func convert(amount: Double, from: String, to: String) -> Double?
}

struct NoOpCurrencyRateProvider: CurrencyRateProvider {
    func convert(amount: Double, from: String, to: String) -> Double? { nil }
}
