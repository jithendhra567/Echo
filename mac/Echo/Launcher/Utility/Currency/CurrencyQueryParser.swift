import Foundation

enum CurrencyQueryParser {

    static func parse(_ query: String) -> CurrencyQuery? {
        let norm = UtilityQueryNormalizer.normalize(query)
        let s = norm.lowercased

        guard let sep = s.range(of: #"\s+(?:to|in)\s+"#, options: .regularExpression) else {
            return nil
        }

        let left = String(s[..<sep.lowerBound]).trimmingCharacters(in: .whitespaces)
        let right = String(s[sep.upperBound...]).trimmingCharacters(in: .whitespaces)
        guard !left.isEmpty, !right.isEmpty else { return nil }

        guard let (amount, from) = CurrencyLexicon.parseAmountAndCurrency(left),
              let to = CurrencyLexicon.resolve(right) else {
            return nil
        }

        guard from != to else { return nil }
        return CurrencyQuery(amount: amount, fromCode: from, toCode: to)
    }
}
