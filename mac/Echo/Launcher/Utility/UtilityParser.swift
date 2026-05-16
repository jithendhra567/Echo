import Foundation

/// Routes launcher search queries to local utility engines (no LLM).
/// Currency conversion is handled asynchronously via `CurrencyConversionService`.
enum UtilityParser {

    static func parse(_ query: String) -> UtilityResult? {
        let norm = UtilityQueryNormalizer.normalize(query)
        guard !norm.trimmed.isEmpty else { return nil }

        // Currency queries are resolved async — skip here.
        if CurrencyQueryParser.parse(query) != nil { return nil }

        // 1. Timestamp keywords & literals
        if let r = TimestampEngine.evaluate(norm) { return r }

        // 2. World clock & timezone conversion
        if let r = WorldTimeEngine.evaluate(norm) { return r }

        // 3. Date/time natural language
        if let r = DateTimeEngine.evaluate(norm) { return r }

        // 4. Physical unit conversion
        if let r = UnitConversionEngine.evaluate(norm) { return r }

        // 5–6. Percentages & arithmetic
        if let r = CalculationEngine.evaluate(norm) { return r }

        return nil
    }
}
