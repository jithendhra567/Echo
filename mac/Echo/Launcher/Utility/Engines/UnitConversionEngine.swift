import Foundation

enum UnitConversionEngine {

    static func evaluate(_ norm: UtilityQueryNormalizer.NormalizedQuery) -> UtilityResult? {
        let s = norm.lowercased

        guard let sep = s.range(of: #"\s+(?:to|in)\s+"#, options: .regularExpression) else {
            return nil
        }

        let left = String(s[..<sep.lowerBound]).trimmingCharacters(in: .whitespaces)
        let right = String(s[sep.upperBound...]).trimmingCharacters(in: .whitespaces)
        guard !left.isEmpty, !right.isEmpty else { return nil }

        guard let (amount, fromDef) = UnitLexicon.parseAmountAndUnit(left),
              let toDef = UnitLexicon.resolve(right) else {
            return nil
        }

        if fromDef.category == .storage, toDef.category == .storage {
            return convertStorage(amount: amount, from: fromDef, to: toDef)
        }

        guard fromDef.category == toDef.category else { return nil }

        switch fromDef.category {
        case .length:
            return convertLength(amount: amount, from: fromDef, to: toDef)
        case .weight:
            return convertWeight(amount: amount, from: fromDef, to: toDef)
        case .temperature:
            return convertTemperature(amount: amount, from: fromDef, to: toDef)
        case .storage:
            return nil
        }
    }

    // MARK: - Converters

    private static func convertLength(amount: Double, from: UnitLexicon.UnitDefinition, to: UnitLexicon.UnitDefinition) -> UtilityResult? {
        guard let fu = from.lengthUnit, let tu = to.lengthUnit else { return nil }
        let m = Measurement(value: amount, unit: fu)
        let out = m.converted(to: tu).value
        return unitResult(value: out, unitId: to.id)
    }

    private static func convertWeight(amount: Double, from: UnitLexicon.UnitDefinition, to: UnitLexicon.UnitDefinition) -> UtilityResult? {
        guard let fu = from.massUnit, let tu = to.massUnit else { return nil }
        let m = Measurement(value: amount, unit: fu)
        let out = m.converted(to: tu).value
        return unitResult(value: out, unitId: to.id)
    }

    private static func convertTemperature(amount: Double, from: UnitLexicon.UnitDefinition, to: UnitLexicon.UnitDefinition) -> UtilityResult? {
        guard let fu = from.temperatureUnit, let tu = to.temperatureUnit else { return nil }
        let m = Measurement(value: amount, unit: fu)
        let out = m.converted(to: tu).value
        return unitResult(value: out, unitId: to.id)
    }

    private static func convertStorage(amount: Double, from: UnitLexicon.UnitDefinition, to: UnitLexicon.UnitDefinition) -> UtilityResult? {
        guard let ff = from.storageFactor, let tf = to.storageFactor else { return nil }
        let bytes = amount * ff
        let out = bytes / tf
        return unitResult(value: out, unitId: to.id)
    }

    private static func unitResult(value: Double, unitId: String) -> UtilityResult? {
        guard value.isFinite else { return nil }
        let text = formatMeasurement(value, unitId: unitId)
        return UtilityResult(
            kind: .unitConversion,
            copyText: text,
            previewText: text,
            detailText: nil
        )
    }

    private static func formatMeasurement(_ value: Double, unitId: String) -> String {
        let formatted = CalculationEngine.formatNumber(value)
        return "\(formatted) \(unitId)"
    }
}
