import Foundation

enum UtilityQueryNormalizer {

    struct NormalizedQuery {
        let raw: String
        let trimmed: String
        let lowercased: String
        let hasLeadingEquals: Bool
        /// Expression body after stripping optional leading `=`.
        let expression: String
    }

  private static let typoCorrections: [(String, String)] = [
    ("tomorow", "tomorrow"),
    ("tommorow", "tomorrow"),
    ("firday", "friday"),
    ("wensday", "wednesday"),
    ("thrusday", "thursday"),
    ("tuseday", "tuesday"),
    ("celcius", "celsius"),
    ("farenheit", "fahrenheit"),
    ("miliseconds", "milliseconds"),
  ]

    static func normalize(_ query: String) -> NormalizedQuery {
        var trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasLeadingEquals = trimmed.hasPrefix("=")
        let expression: String
        if hasLeadingEquals {
            expression = String(trimmed.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            expression = trimmed
        }

        var lower = expression.lowercased()
        lower = collapseWhitespace(lower)
        lower = applyTypoCorrections(lower)

        trimmed = collapseWhitespace(trimmed)
        return NormalizedQuery(
            raw: query,
            trimmed: trimmed,
            lowercased: lower,
            hasLeadingEquals: hasLeadingEquals,
            expression: expression
        )
    }

    /// Removes thousands separators inside numeric tokens for arithmetic.
    static func stripCommasForMath(_ s: String) -> String {
        s.replacingOccurrences(of: ",", with: "")
    }

    private static func collapseWhitespace(_ s: String) -> String {
        s.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    private static func applyTypoCorrections(_ s: String) -> String {
        var out = s
        for (wrong, right) in typoCorrections {
            out = out.replacingOccurrences(of: wrong, with: right)
        }
        return out
    }
}
