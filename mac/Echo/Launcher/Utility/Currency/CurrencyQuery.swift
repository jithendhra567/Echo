import Foundation

struct CurrencyQuery: Sendable, Equatable {
    let amount: Double
    let fromCode: String
    let toCode: String
}
