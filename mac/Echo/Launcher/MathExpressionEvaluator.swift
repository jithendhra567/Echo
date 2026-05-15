import Foundation

/// Spotlight-style arithmetic for the launcher search field.
enum MathExpressionEvaluator {

    /// Evaluates `query` when it looks like an intentional math expression.
    /// Returns a display/copy string on success, or `nil`.
    static func evaluate(_ query: String) -> String? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let hasLeadingEquals = trimmed.hasPrefix("=")
        let expression = hasLeadingEquals
            ? String(trimmed.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
            : trimmed
        guard !expression.isEmpty else { return nil }

        guard isAllowed(expression) else { return nil }
        guard looksIntentional(expression, hasLeadingEquals: hasLeadingEquals) else { return nil }

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
        return format(value)
    }

    // MARK: - Validation

    private static let allowedCharset: CharacterSet = {
        var set = CharacterSet(charactersIn: "0123456789.+-*/()")
        set.formUnion(.whitespacesAndNewlines)
        return set
    }()

    private static func isAllowed(_ expression: String) -> Bool {
        expression.unicodeScalars.allSatisfy { allowedCharset.contains($0) }
    }

    /// Require `=` prefix or at least one operator / parentheses so plain text
    /// like `Notes` or bare `12` do not show a calculator row.
    private static func looksIntentional(_ expression: String, hasLeadingEquals: Bool) -> Bool {
        if hasLeadingEquals { return true }
        return expression.contains(where: { "+-*/()".contains($0) })
    }

    // MARK: - Formatting

    private static func format(_ value: Double) -> String {
        if value.rounded(.towardZero) == value, abs(value) < 1e15 {
            return String(Int(value))
        }
        return String(format: "%g", value)
    }
}
