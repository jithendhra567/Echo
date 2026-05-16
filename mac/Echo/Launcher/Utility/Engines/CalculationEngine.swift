import Foundation

enum CalculationEngine {

    static func evaluate(_ norm: UtilityQueryNormalizer.NormalizedQuery) -> UtilityResult? {
        if let r = evaluatePercentages(norm) { return r }
        return evaluateArithmetic(norm)
    }

    // MARK: - Percentages

    private static let num = #"(\d+(?:\.\d+)?)"#

    private static func evaluatePercentages(_ norm: UtilityQueryNormalizer.NormalizedQuery) -> UtilityResult? {
        let s = norm.lowercased
        guard s.contains("%") else { return nil }

        if let m = firstMatch(#"^\#(num)\s*%\s*of\s*\#(num)$"#, in: s),
           let pct = captureDouble(m, 1, in: s), let base = captureDouble(m, 2, in: s) {
            return percentResult(value: base * pct / 100)
        }

        if let m = firstMatch(#"^\#(num)\s*%\s*off\s*\#(num)$"#, in: s),
           let pct = captureDouble(m, 1, in: s), let base = captureDouble(m, 2, in: s) {
            let result = base * (1 - pct / 100)
            return UtilityResult(
                kind: .percentage,
                copyText: formatNumber(result),
                previewText: formatNumber(result),
                detailText: "After \(formatNumber(pct))% off"
            )
        }

        if let m = firstMatch(#"^\#(num)\s*%\s*tip\s+on\s+\#(num)$"#, in: s),
           let pct = captureDouble(m, 1, in: s), let base = captureDouble(m, 2, in: s) {
            let tip = base * pct / 100
            let total = base + tip
            return UtilityResult(
                kind: .percentage,
                copyText: formatNumber(tip),
                previewText: formatNumber(tip),
                detailText: "Tip · Total \(formatNumber(total))"
            )
        }

        if let m = firstMatch(#"^\#(num)\s*\+\s*\#(num)\s*%$"#, in: s),
           let base = captureDouble(m, 1, in: s), let pct = captureDouble(m, 2, in: s) {
            return percentResult(value: base * (1 + pct / 100))
        }

        if let m = firstMatch(#"^\#(num)\s*-\s*\#(num)\s*%$"#, in: s),
           let base = captureDouble(m, 1, in: s), let pct = captureDouble(m, 2, in: s) {
            return percentResult(value: base * (1 - pct / 100))
        }

        return nil
    }

    private static func percentResult(value: Double) -> UtilityResult? {
        guard value.isFinite else { return nil }
        let text = formatNumber(value)
        return UtilityResult(kind: .percentage, copyText: text, previewText: text)
    }

    // MARK: - Arithmetic

    private static let allowedCharset: CharacterSet = {
        var set = CharacterSet(charactersIn: "0123456789.+-*/()")
        set.formUnion(.whitespacesAndNewlines)
        return set
    }()

    private static func evaluateArithmetic(_ norm: UtilityQueryNormalizer.NormalizedQuery) -> UtilityResult? {
        let expression = UtilityQueryNormalizer.stripCommasForMath(norm.expression)
        guard !expression.isEmpty else { return nil }
        guard expression.unicodeScalars.allSatisfy({ allowedCharset.contains($0) }) else { return nil }
        guard looksIntentionalArithmetic(expression, hasLeadingEquals: norm.hasLeadingEquals) else { return nil }

        let value: Double
        do {
            let expr = try NSExpression(format: expression)
            guard let raw = expr.expressionValue(with: nil, context: nil) else { return nil }
            if let n = raw as? NSNumber {
                value = n.doubleValue
            } else if let d = raw as? Double {
                value = d
            } else {
                return nil
            }
        } catch {
            return nil
        }

        guard value.isFinite else { return nil }
        let text = formatNumber(value)
        return UtilityResult(kind: .calculation, copyText: text, previewText: text)
    }

    private static func looksIntentionalArithmetic(_ expression: String, hasLeadingEquals: Bool) -> Bool {
        if hasLeadingEquals { return true }
        return expression.contains(where: { "+-*/()".contains($0) })
    }

    // MARK: - Helpers

    nonisolated static func formatNumber(_ value: Double) -> String {
        if value.rounded(.towardZero) == value, abs(value) < 1e15 {
            return String(Int(value))
        }
        return String(format: "%g", value)
    }

    private static func firstMatch(_ pattern: String, in s: String) -> NSTextCheckingResult? {
        guard let re = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return nil }
        return re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s))
    }

    private static func captureDouble(_ m: NSTextCheckingResult, _ group: Int, in s: String) -> Double? {
        guard group < m.numberOfRanges,
              let r = Range(m.range(at: group), in: s) else { return nil }
        return Double(s[r])
    }
}
