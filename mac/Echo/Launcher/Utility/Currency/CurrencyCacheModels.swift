import Foundation

struct CurrencyCacheEntry: Sendable {
    let base: String
    let target: String
    let rate: Double
    var fetchedAt: Date
    var lastUsed: Date

    nonisolated static func key(base: String, target: String) -> String {
        "\(base.uppercased()):\(target.uppercased())"
    }
}

struct CurrencyCacheSnapshot: Sendable {
    var entries: [String: CurrencyCacheEntry]
    var lastCurrencyActivityAt: Date?
}

enum CurrencyCachePolicy: Sendable {
    nonisolated static let refreshInterval: TimeInterval = 12 * 60 * 60
    nonisolated static let inactivityCleanup: TimeInterval = 3 * 24 * 60 * 60
}
