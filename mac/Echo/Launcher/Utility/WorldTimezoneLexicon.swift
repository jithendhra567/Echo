import Foundation

/// Maps country / city / region names and common abbreviations to IANA timezone ids.
enum WorldTimezoneLexicon {

    private static let table: [String: String] = {
        var m = [String: String]()
        func r(_ zone: String, _ keys: String...) {
            for k in keys { m[k.lowercased()] = zone }
        }

        r("Europe/Warsaw", "poland", "polish", "warsaw", "krakow", "gdansk")
        r("Asia/Kolkata", "india", "indian", "mumbai", "delhi", "bangalore", "kolkata", "chennai",
          "hyderabad", "bengaluru", "pune")
        r("Asia/Tokyo", "japan", "japanese", "tokyo", "osaka", "kyoto")
        r("Asia/Shanghai", "china", "chinese", "beijing", "shanghai")
        r("Asia/Hong_Kong", "hong kong", "hongkong", "hk")
        r("Asia/Seoul", "south korea", "korea", "seoul")
        r("Asia/Pyongyang", "north korea")
        r("Asia/Taipei", "taiwan", "taipei")
        r("Asia/Bangkok", "thailand", "bangkok")
        r("Asia/Ho_Chi_Minh", "vietnam", "hanoi", "ho chi minh")
        r("Asia/Singapore", "singapore")
        r("Asia/Kuala_Lumpur", "malaysia", "kuala lumpur")
        r("Asia/Jakarta", "indonesia", "jakarta")
        r("Asia/Manila", "philippines", "manila")
        r("Australia/Sydney", "australia", "sydney", "canberra")
        r("Australia/Melbourne", "melbourne")
        r("Australia/Brisbane", "brisbane")
        r("Australia/Perth", "perth")
        r("Pacific/Auckland", "new zealand", "auckland")
        r("Europe/London", "uk", "britain", "british", "england", "london", "scotland", "edinburgh",
          "wales", "cardiff", "northern ireland", "belfast")
        r("Europe/Dublin", "ireland", "dublin")
        r("Europe/Paris", "france", "french", "paris", "lyon")
        r("Europe/Berlin", "germany", "german", "berlin", "munich", "frankfurt", "hamburg")
        r("Europe/Rome", "italy", "italian", "rome", "milan")
        r("Europe/Madrid", "spain", "spanish", "madrid", "barcelona")
        r("Europe/Lisbon", "portugal", "lisbon")
        r("Europe/Amsterdam", "netherlands", "dutch", "amsterdam")
        r("Europe/Brussels", "belgium", "brussels")
        r("Europe/Zurich", "switzerland", "zurich", "geneva")
        r("Europe/Vienna", "austria", "vienna")
        r("Europe/Stockholm", "sweden", "stockholm")
        r("Europe/Oslo", "norway", "oslo")
        r("Europe/Copenhagen", "denmark", "copenhagen")
        r("Europe/Helsinki", "finland", "helsinki")
        r("Atlantic/Reykjavik", "iceland", "reykjavik")
        r("Europe/Athens", "greece", "athens")
        r("Europe/Prague", "czech", "czechia", "prague")
        r("Europe/Budapest", "hungary", "budapest")
        r("Europe/Bucharest", "romania", "bucharest")
        r("Europe/Sofia", "bulgaria", "sofia")
        r("Europe/Istanbul", "turkey", "turkish", "istanbul", "ankara")
        r("Asia/Jerusalem", "israel", "tel aviv", "jerusalem")
        r("Asia/Dubai", "uae", "dubai", "abu dhabi")
        r("Asia/Riyadh", "saudi", "riyadh")
        r("Asia/Qatar", "qatar", "doha")
        r("Asia/Kuwait", "kuwait")
        r("Africa/Cairo", "egypt", "cairo")
        r("Africa/Johannesburg", "south africa", "johannesburg", "cape town")
        r("Africa/Lagos", "nigeria", "lagos")
        r("Africa/Nairobi", "kenya", "nairobi")
        r("America/Mexico_City", "mexico", "mexico city", "cdmx")
        r("America/Sao_Paulo", "brazil", "brasilia", "sao paulo", "rio")
        r("America/Argentina/Buenos_Aires", "argentina", "buenos aires")
        r("America/Santiago", "chile", "santiago")
        r("America/Bogota", "colombia", "bogota")
        r("America/Lima", "peru", "lima")
        r("America/Toronto", "canada", "canadian", "toronto", "montreal")
        r("America/Vancouver", "vancouver")
        r("America/Edmonton", "calgary")
        r("America/New_York", "usa", "us", "america", "united states", "nyc", "new york", "newyork",
          "boston", "washington", "miami", "atlanta", "philadelphia", "est", "eastern", "et")
        r("America/Chicago", "chicago", "texas", "dallas", "houston", "cst", "central", "ct")
        r("America/Denver", "denver", "colorado", "utah", "salt lake", "mst", "mountain", "mt")
        r("America/Los_Angeles", "california", "los angeles", "la", "san francisco", "sf", "seattle",
          "portland", "pst", "pacific", "pt")
        r("America/Anchorage", "alaska", "anchorage", "akst", "akt")
        r("Pacific/Honolulu", "hawaii", "honolulu", "hst", "ht")
        r("Europe/Moscow", "russia", "moscow")
        r("Europe/Kyiv", "ukraine", "kyiv", "kiev")
        r("Asia/Karachi", "pakistan", "karachi", "lahore")
        r("Asia/Dhaka", "bangladesh", "dhaka")
        r("Asia/Kathmandu", "nepal", "kathmandu")
        r("Asia/Colombo", "sri lanka", "colombo")

        r("UTC", "utc", "gmt", "zulu")
        r("Asia/Tokyo", "jst")
        r("Asia/Kolkata", "ist", "india standard time")
        r("Australia/Sydney", "aest")
        r("Australia/Perth", "awst")

        return m
    }()

    /// Single-token and multi-token resolution (longest phrase first).
    static func resolveIANA(_ raw: String) -> String? {
        let key = raw.trimmingCharacters(in: .whitespaces).lowercased()
        guard !key.isEmpty else { return nil }

        if let id = table[key] { return id }

        let tokens = key.split(separator: " ").map(String.init)
        for len in stride(from: min(4, tokens.count), through: 1, by: -1) {
            for start in 0...(tokens.count - len) {
                let phrase = tokens[start..<(start + len)].joined(separator: " ")
                if let id = table[phrase] { return id }
            }
        }

        let underscored = key.replacingOccurrences(of: " ", with: "_")
        if TimeZone(identifier: underscored) != nil { return underscored }

        return nil
    }

    static func timeZone(forPlace raw: String) -> TimeZone? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let id = resolveIANA(trimmed), let tz = TimeZone(identifier: id) {
            return tz
        }

        if let tz = TimeZone(identifier: trimmed) { return tz }
        if let tz = TimeZone(identifier: trimmed.replacingOccurrences(of: " ", with: "_")) { return tz }

        if let tz = resolveGMTStyle(trimmed) { return tz }

        return nil
    }

    /// Parses `utc+5`, `gmt-4:30`.
    private static func resolveGMTStyle(_ s: String) -> TimeZone? {
        let t = s.replacingOccurrences(of: " ", with: "").lowercased()
        guard let r = try? NSRegularExpression(pattern: #"^(gmt|utc)([+-])(\d{1,2})(?::(\d{2}))?$"#, options: .caseInsensitive),
              let m = r.firstMatch(in: t, range: NSRange(t.startIndex..., in: t)),
              let signr = Range(m.range(at: 2), in: t),
              let hr = Range(m.range(at: 3), in: t),
              let hours = Int(t[hr]) else { return nil }

        var secs = hours * 3600
        if m.numberOfRanges > 4, m.range(at: 4).location != NSNotFound,
           let mr = Range(m.range(at: 4), in: t), let mins = Int(t[mr]) {
            secs += mins * 60
        }
        if t[signr].lowercased() == "-" { secs = -secs }
        return TimeZone(secondsFromGMT: secs)
    }
}
