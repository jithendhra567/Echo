import Foundation

enum CurrencyLexicon {

    private static let codes: Set<String> = [
        "USD", "EUR", "GBP", "INR", "JPY", "CAD", "AUD", "CHF", "CNY", "HKD",
        "SGD", "NZD", "KRW", "MXN", "BRL", "ZAR", "SEK", "NOK", "DKK", "PLN",
        "THB", "IDR", "MYR", "PHP", "CZK", "HUF", "ILS", "TRY", "RON", "BGN",
    ]

    private static let aliases: [String: String] = [
        "usd": "USD", "dollar": "USD", "dollars": "USD", "usd$": "USD",
        "eur": "EUR", "euro": "EUR", "euros": "EUR",
        "gbp": "GBP", "pound": "GBP", "pounds": "GBP",
        "inr": "INR", "rupee": "INR", "rupees": "INR", "rs": "INR", "rs.": "INR",
        "jpy": "JPY", "yen": "JPY",
        "cad": "CAD", "c$": "CAD",
        "aud": "AUD", "a$": "AUD",
        "chf": "CHF", "franc": "CHF",
        "cny": "CNY", "yuan": "CNY", "rmb": "CNY",
        "hkd": "HKD",
        "sgd": "SGD",
        "nzd": "NZD",
        "krw": "KRW", "won": "KRW",
        "mxn": "MXN",
        "brl": "BRL", "real": "BRL",
        "zar": "ZAR", "rand": "ZAR",
    ]

    /// Unicode symbols → ISO (single-char and common).
    private static let symbolToCodeOrdered: [(String, String)] = [
        ("₹", "INR"),
        ("€", "EUR"),
        ("£", "GBP"),
        ("¥", "JPY"),
        ("₩", "KRW"),
        ("$", "USD"),
    ]

    static func resolve(_ token: String) -> String? {
        var t = token.trimmingCharacters(in: .whitespaces).lowercased()
        if t.hasSuffix(".") { t.removeLast() }
        guard !t.isEmpty else { return nil }
        if let code = aliases[t] { return code }
        let upper = t.uppercased()
        if upper.count == 3, codes.contains(upper) { return upper }
        return nil
    }

    /// Parses `100usd`, `4k$`, `$4k`, `€50`, `₹ 1000`, `100 usd`, `1,000.50 eur`.
    static func parseAmountAndCurrency(_ raw: String) -> (amount: Double, code: String)? {
        var t = raw.trimmingCharacters(in: .whitespaces).lowercased()
        guard !t.isEmpty else { return nil }

        var symbolHint: String?

        for _ in 0..<4 {
            let before = t
            t = t.trimmingCharacters(in: .whitespaces)
            for (sym, code) in symbolToCodeOrdered {
                if t.hasPrefix(sym) {
                    symbolHint = symbolHint ?? code
                    t = String(t.dropFirst(sym.count)).trimmingCharacters(in: .whitespaces)
                }
                if t.hasSuffix(sym) {
                    symbolHint = symbolHint ?? code
                    t = String(t.dropLast(sym.count)).trimmingCharacters(in: .whitespaces)
                }
            }
            if t == before { break }
        }

        let aliasPairs = aliases.keys.sorted { $0.count > $1.count }
        for alias in aliasPairs {
            guard t.hasSuffix(alias), let code = aliases[alias] else { continue }
            let numPart = normalizeNumberPart(String(t.dropLast(alias.count)))
            guard let amount = parseScaledNumber(numPart) else { continue }
            return (amount, code)
        }

        let parts = t.split(separator: " ", omittingEmptySubsequences: true)
        if parts.count == 2 {
            let numStr = normalizeNumberPart(String(parts[0]))
            if let amount = parseScaledNumber(numStr), let code = resolve(String(parts[1])) {
                return (amount, code)
            }
        }

        if let amount = parseScaledNumber(normalizeNumberPart(t)), let hint = symbolHint {
            return (amount, hint)
        }

        if symbolHint == nil,
           looksLikeBareAmount(t),
           let amount = parseScaledNumber(normalizeNumberPart(t)) {
            return (amount, "USD")
        }

        if let code = resolve(t) { return (1, code) }
        return nil
    }

    private static func normalizeNumberPart(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: ",", with: "")
    }

    private static func looksLikeBareAmount(_ s: String) -> Bool {
        let allowed = CharacterSet(charactersIn: "0123456789.,kmb")
        return s.lowercased().unicodeScalars.allSatisfy { allowed.contains($0) }
    }

    /// Parses `4`, `4k`, `1.5m`, `2b` (decimal thousands / millions / billions).
    private static func parseScaledNumber(_ s: String) -> Double? {
        let u = s.lowercased().trimmingCharacters(in: .whitespaces)
        guard !u.isEmpty else { return nil }

        guard let re = try? NSRegularExpression(pattern: #"^(\d+(?:\.\d+)?)\s*([kmb])?$"#, options: .caseInsensitive),
              let match = re.firstMatch(in: u, range: NSRange(u.startIndex..., in: u)),
              let r1 = Range(match.range(at: 1), in: u),
              let base = Double(String(u[r1])) else { return nil }

        var mult = 1.0
        let r2 = match.range(at: 2)
        if r2.location != NSNotFound, let sr = Range(r2, in: u) {
            switch String(u[sr]).lowercased() {
            case "k": mult = 1_000
            case "m": mult = 1_000_000
            case "b": mult = 1_000_000_000
            default: break
            }
        }
        return base * mult
    }
}
