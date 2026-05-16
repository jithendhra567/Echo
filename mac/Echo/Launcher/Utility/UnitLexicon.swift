import Foundation

enum UnitLexicon {

    enum UnitCategory: Sendable {
        case length
        case storage
        case weight
        case temperature
    }

    struct UnitDefinition: Sendable {
        let id: String
        let category: UnitCategory
        let aliases: [String]
        /// For Foundation Measurement types.
        let lengthUnit: UnitLength?
        let massUnit: UnitMass?
        let temperatureUnit: UnitTemperature?
        /// Decimal multiplier for storage (bytes scale).
        let storageFactor: Double?
    }

    static let definitions: [UnitDefinition] = [
        // Length
        UnitDefinition(id: "ft", category: .length, aliases: ["ft", "foot", "feet"], lengthUnit: .feet, massUnit: nil, temperatureUnit: nil, storageFactor: nil),
        UnitDefinition(id: "cm", category: .length, aliases: ["cm", "centimeter", "centimeters", "centimetre", "centimetres"], lengthUnit: .centimeters, massUnit: nil, temperatureUnit: nil, storageFactor: nil),
        UnitDefinition(id: "km", category: .length, aliases: ["km", "kilometer", "kilometers", "kilometre", "kilometres"], lengthUnit: .kilometers, massUnit: nil, temperatureUnit: nil, storageFactor: nil),
        UnitDefinition(id: "mi", category: .length, aliases: ["mi", "mile", "miles"], lengthUnit: .miles, massUnit: nil, temperatureUnit: nil, storageFactor: nil),
        UnitDefinition(id: "in", category: .length, aliases: ["in", "inch", "inches"], lengthUnit: .inches, massUnit: nil, temperatureUnit: nil, storageFactor: nil),
        UnitDefinition(id: "mm", category: .length, aliases: ["mm", "millimeter", "millimeters", "millimetre", "millimetres"], lengthUnit: .millimeters, massUnit: nil, temperatureUnit: nil, storageFactor: nil),
        UnitDefinition(id: "m", category: .length, aliases: ["m", "meter", "meters", "metre", "metres"], lengthUnit: .meters, massUnit: nil, temperatureUnit: nil, storageFactor: nil),
        // Storage (decimal 1000-based)
        UnitDefinition(id: "gb", category: .storage, aliases: ["gb", "gigabyte", "gigabytes"], lengthUnit: nil, massUnit: nil, temperatureUnit: nil, storageFactor: 1_000_000_000),
        UnitDefinition(id: "mb", category: .storage, aliases: ["mb", "megabyte", "megabytes"], lengthUnit: nil, massUnit: nil, temperatureUnit: nil, storageFactor: 1_000_000),
        UnitDefinition(id: "kb", category: .storage, aliases: ["kb", "kilobyte", "kilobytes"], lengthUnit: nil, massUnit: nil, temperatureUnit: nil, storageFactor: 1_000),
        // Weight
        UnitDefinition(id: "kg", category: .weight, aliases: ["kg", "kilogram", "kilograms", "kilo", "kilos"], lengthUnit: nil, massUnit: .kilograms, temperatureUnit: nil, storageFactor: nil),
        UnitDefinition(id: "lb", category: .weight, aliases: ["lb", "lbs", "pound", "pounds"], lengthUnit: nil, massUnit: .pounds, temperatureUnit: nil, storageFactor: nil),
        // Temperature
        UnitDefinition(id: "c", category: .temperature, aliases: ["c", "celsius", "centigrade", "°c"], lengthUnit: nil, massUnit: nil, temperatureUnit: .celsius, storageFactor: nil),
        UnitDefinition(id: "f", category: .temperature, aliases: ["f", "fahrenheit", "°f"], lengthUnit: nil, massUnit: nil, temperatureUnit: .fahrenheit, storageFactor: nil),
    ]

    static func resolve(_ token: String) -> UnitDefinition? {
        let t = token.lowercased().trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return nil }
        if let exact = definitions.first(where: { $0.aliases.contains(t) }) {
            return exact
        }
        var best: (UnitDefinition, Int)?
        for def in definitions {
            for alias in def.aliases {
                let d = levenshtein(t, alias)
                if d <= 1, d < (best?.1 ?? Int.max) {
                    best = (def, d)
                }
            }
        }
        return best?.0
    }

    /// Parses `5.8ft`, `5.8 ft`, `10km`, etc. into amount + unit (longest alias wins).
    static func parseAmountAndUnit(_ raw: String) -> (amount: Double, definition: UnitDefinition)? {
        let t = raw.trimmingCharacters(in: .whitespaces).lowercased()
        guard !t.isEmpty else { return nil }

        let aliasPairs: [(String, UnitDefinition)] = definitions.flatMap { def in
            def.aliases.map { ($0, def) }
        }.sorted { $0.0.count > $1.0.count }

        for (alias, def) in aliasPairs {
            guard t.hasSuffix(alias) else { continue }
            let numPart = String(t.dropLast(alias.count)).trimmingCharacters(in: .whitespaces)
            guard !numPart.isEmpty, let amount = Double(numPart) else { continue }
            return (amount, def)
        }

        let parts = t.split(separator: " ", omittingEmptySubsequences: true)
        if parts.count == 2,
           let amount = Double(parts[0]),
           let def = resolve(String(parts[1])) {
            return (amount, def)
        }
        return nil
    }

    private static func levenshtein(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        var row = Array(0...b.count)
        for i in 1...a.count {
            var prev = row[0]
            row[0] = i
            for j in 1...b.count {
                let temp = row[j]
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                row[j] = min(row[j] + 1, row[j - 1] + 1, prev + cost)
                prev = temp
            }
        }
        return row[b.count]
    }
}
