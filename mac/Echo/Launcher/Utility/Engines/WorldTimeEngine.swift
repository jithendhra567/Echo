import Foundation

/// World clock and timezone conversion (deterministic, no network).
enum WorldTimeEngine {

    // MARK: - Public

    static func evaluate(_ norm: UtilityQueryNormalizer.NormalizedQuery) -> UtilityResult? {
        var s = norm.lowercased
        if s.hasPrefix("convert ") {
            s = String(s.dropFirst("convert ".count)).trimmingCharacters(in: .whitespaces)
        }
        if let r = tryConversion(s) { return r }
        if let r = tryCurrentTime(s) { return r }
        return nil
    }

    // MARK: - Current time elsewhere

    private static func tryCurrentTime(_ s: String) -> UtilityResult? {
        let place: String?
        if let m = firstMatch(#"^time\s+in\s+(.+)$"#, in: s) { place = capture(m, 1, in: s) }
        else if let m = firstMatch(#"^time\s+at\s+(.+)$"#, in: s) { place = capture(m, 1, in: s) }
        else if let m = firstMatch(#"^what(?:'s| is)\s+time\s+in\s+(.+)$"#, in: s) { place = capture(m, 1, in: s) }
        else if let m = firstMatch(#"^what(?:'s| is)\s+the\s+time\s+in\s+(.+)$"#, in: s) { place = capture(m, 1, in: s) }
        else         if let m = firstMatch(#"^current\s+time\s+in\s+(.+)$"#, in: s) { place = capture(m, 1, in: s) }
        else if let m = firstMatch(#"^time\s+(?!in\s)(?!at\s)(.+)$"#, in: s) { place = capture(m, 1, in: s) }
        else if let m = firstMatch(#"^(.{2,})\s+time(?:\s+now)?$"#, in: s) { place = capture(m, 1, in: s) }
        else if let m = firstMatch(#"^(.{2,})\s+timezone$"#, in: s) { place = capture(m, 1, in: s) }
        else { place = nil }

        guard let rawPlace = place?.trimmingCharacters(in: .whitespaces), rawPlace.count >= 2,
              let tz = WorldTimezoneLexicon.timeZone(forPlace: rawPlace) else {
            return nil
        }

        return nowResult(remoteTZ: tz, label: rawPlace)
    }

    private static func nowResult(remoteTZ: TimeZone, label: String) -> UtilityResult {
        let now = Date()
        let remoteStr = format(date: now, in: remoteTZ, dateStyle: .medium, timeStyle: .short)
        let localStr = format(date: now, in: TimeZone.current, dateStyle: .none, timeStyle: .short)
        let iana = remoteTZ.identifier
        let diff = offsetVsLocal(target: remoteTZ, at: now)

        return UtilityResult(
            kind: .dateTime,
            copyText: "\(remoteStr) (\(iana))",
            previewText: remoteStr,
            detailText: "\(iana) · \(diff) · Here: \(localStr)"
        )
    }

    // MARK: - Conversion (wall time in A → instant → display in B)

    private static func tryConversion(_ s: String) -> UtilityResult? {
        if let r = matchConversion24h(s) { return r }
        if let r = matchConversion12h(s) { return r }
        return nil
    }

    private static func matchConversion24h(_ s: String) -> UtilityResult? {
        guard let m = firstMatch(#"^(\d{1,2}):(\d{2})\s+(.+?)\s+to\s+(.+)$"#, in: s),
              let h = Int(capture(m, 1, in: s) ?? ""),
              let min = Int(capture(m, 2, in: s) ?? ""),
              h >= 0, h <= 23, min >= 0, min <= 59,
              let srcName = capture(m, 3, in: s),
              let dstName = capture(m, 4, in: s),
              let src = WorldTimezoneLexicon.timeZone(forPlace: srcName.trimmingCharacters(in: .whitespaces)),
              let dst = WorldTimezoneLexicon.timeZone(forPlace: dstName.trimmingCharacters(in: .whitespaces)),
              src.identifier != dst.identifier else { return nil }

        return convertWallTime(hour24: h, minute: min, from: src, to: dst, sourceLabel: srcName, destLabel: dstName)
    }

    private static func matchConversion12h(_ s: String) -> UtilityResult? {
        guard let m = firstMatch(#"^(\d{1,2})(?::(\d{2}))?\s*(am|pm)\s+(.+?)\s+to\s+(.+)$"#, in: s),
              var h = Int(capture(m, 1, in: s) ?? ""),
              let ap = capture(m, 3, in: s)?.lowercased(),
              let srcName = capture(m, 4, in: s),
              let dstName = capture(m, 5, in: s),
              let src = WorldTimezoneLexicon.timeZone(forPlace: srcName.trimmingCharacters(in: .whitespaces)),
              let dst = WorldTimezoneLexicon.timeZone(forPlace: dstName.trimmingCharacters(in: .whitespaces)) else {
            return nil
        }

        let min = Int(capture(m, 2, in: s) ?? "") ?? 0
        guard h >= 1, h <= 12, min >= 0, min <= 59 else { return nil }

        if ap == "pm", h != 12 { h += 12 }
        if ap == "am", h == 12 { h = 0 }

        return convertWallTime(hour24: h, minute: min, from: src, to: dst, sourceLabel: srcName, destLabel: dstName)
    }

    private static func convertWallTime(
        hour24: Int,
        minute: Int,
        from src: TimeZone,
        to dst: TimeZone,
        sourceLabel: String,
        destLabel: String
    ) -> UtilityResult? {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = src
        let now = Date()
        var base = cal.dateComponents([.year, .month, .day], from: now)
        base.hour = hour24
        base.minute = minute
        base.second = 0
        guard let instant = cal.date(from: base) else { return nil }

        let srcWall = format(date: instant, in: src, dateStyle: .medium, timeStyle: .short)
        let dstWall = format(date: instant, in: dst, dateStyle: .medium, timeStyle: .short)
        let localWall = format(date: instant, in: TimeZone.current, dateStyle: .medium, timeStyle: .short)
        let diffDest = offsetVsLocal(target: dst, at: instant)

        return UtilityResult(
            kind: .dateTime,
            copyText: "\(dstWall) (\(dst.identifier))",
            previewText: dstWall,
            detailText: "\(src.identifier) → \(dst.identifier) · was \(srcWall) · Here: \(localWall) · \(diffDest)"
        )
    }

    // MARK: - Formatting

    private nonisolated static func format(
        date: Date,
        in tz: TimeZone,
        dateStyle: DateFormatter.Style,
        timeStyle: DateFormatter.Style
    ) -> String {
        let f = DateFormatter()
        f.locale = .current
        f.timeZone = tz
        f.dateStyle = dateStyle
        f.timeStyle = timeStyle
        return f.string(from: date)
    }

    private nonisolated static func offsetVsLocal(target: TimeZone, at date: Date) -> String {
        let local = TimeZone.current
        let diff = target.secondsFromGMT(for: date) - local.secondsFromGMT(for: date)
        let h = Double(diff) / 3600.0
        if abs(h) < 0.05 { return "same offset as you" }

        let ahead = h > 0
        let ah = abs(h)
        let mag: String
        if abs(ah - Double(Int(ah))) < 0.01 { mag = "\(Int(ah.rounded()))" }
        else { mag = String(format: "%.1f", ah) }

        return "\(mag)h \(ahead ? "ahead" : "behind") of you"
    }

    // MARK: - Regex

    private static func firstMatch(_ pattern: String, in s: String) -> NSTextCheckingResult? {
        guard let re = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return nil }
        return re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s))
    }

    private static func capture(_ m: NSTextCheckingResult, _ group: Int, in s: String) -> String? {
        guard group < m.numberOfRanges, let r = Range(m.range(at: group), in: s) else { return nil }
        return String(s[r])
    }
}
