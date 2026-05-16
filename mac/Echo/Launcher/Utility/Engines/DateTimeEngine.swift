import Foundation

enum DateTimeEngine {

    private static let weekdays: [(name: String, weekday: Int)] = [
        ("sunday", 1), ("monday", 2), ("tuesday", 3), ("wednesday", 4),
        ("thursday", 5), ("friday", 6), ("saturday", 7),
    ]

    private static let dateSignals = [
        "from now", "from today", "ago", "tomorrow", "yesterday",
        "next ", "this ", "what day", "hours", "hour", "days", "day",
        "weeks", "week", "minutes", "minute", "months", "month", "years", "year",
        "am", "pm", "midnight", "noon",
    ] + weekdays.map(\.name)

    static func evaluate(_ norm: UtilityQueryNormalizer.NormalizedQuery) -> UtilityResult? {
        let s = norm.lowercased
        guard hasDateSignal(s) else { return nil }

        if let r = evaluateTomorrow(s) { return r }
        if let r = evaluateNextWeekday(s) { return r }
        if let r = evaluateAgo(s) { return r }
        if let r = evaluateFromAnchor(s) { return r }
        if let r = evaluateWhatDay(s) { return r }

        return nil
    }

    private static func hasDateSignal(_ s: String) -> Bool {
        dateSignals.contains { s.contains($0) }
    }

    // MARK: - Patterns

    private static func evaluateTomorrow(_ s: String) -> UtilityResult? {
        guard s.hasPrefix("tomorrow") else { return nil }
        let cal = Calendar.current
        guard let base = cal.date(byAdding: .day, value: 1, to: startOfToday(cal)) else { return nil }
        let date = applyTimeSuffix(s, to: base, calendar: cal) ?? base
        return dateResult(date)
    }

    private static func evaluateNextWeekday(_ s: String) -> UtilityResult? {
        guard s.hasPrefix("next ") else { return nil }
        let token = String(s.dropFirst(5)).trimmingCharacters(in: .whitespaces)
        let dayPart = token.split(separator: " ").first.map(String.init) ?? token
        guard let target = weekdays.first(where: { dayPart == $0.name || dayPart.hasPrefix($0.name) })?.weekday else {
            return nil
        }
        let cal = Calendar.current
        guard let date = nextWeekday(target, after: Date(), calendar: cal) else { return nil }
        return dateResult(date)
    }

    private static func evaluateAgo(_ s: String) -> UtilityResult? {
        guard s.hasSuffix(" ago"), let m = durationMatch(in: s, suffix: " ago") else { return nil }
        let cal = Calendar.current
        guard let date = cal.date(byAdding: m.component, value: -m.value, to: Date()) else { return nil }
        return dateResult(date)
    }

    private static func evaluateFromAnchor(_ s: String) -> UtilityResult? {
        if s.hasSuffix(" from now"), let m = durationMatch(in: s, suffix: " from now") {
            let cal = Calendar.current
            guard let date = cal.date(byAdding: m.component, value: m.value, to: Date()) else { return nil }
            return dateResult(date)
        }
        if s.hasSuffix(" from today"), let m = durationMatch(in: s, suffix: " from today") {
            let cal = Calendar.current
            let anchor = startOfToday(cal)
            guard let date = cal.date(byAdding: m.component, value: m.value, to: anchor) else { return nil }
            return dateResult(date)
        }
        return nil
    }

    private static func evaluateWhatDay(_ s: String) -> UtilityResult? {
        guard s.contains("what day"), s.contains("from now") else { return nil }
        guard let m = firstMatch(#"what day is (\d+) (days?|weeks?|months?|years?) from now"#, in: s),
              let n = Int(capture(m, 1, in: s) ?? ""),
              let unit = capture(m, 2, in: s) else { return nil }
        let comp = durationComponent(for: unit)
        let cal = Calendar.current
        guard let date = cal.date(byAdding: comp, value: n, to: Date()) else { return nil }
        return dateResult(date)
    }

    // MARK: - Duration parsing

    private struct DurationMatch {
        let value: Int
        let component: Calendar.Component
    }

    private static func durationMatch(in s: String, suffix: String) -> DurationMatch? {
        let body = String(s.dropLast(suffix.count)).trimmingCharacters(in: .whitespaces)
        guard let m = firstMatch(#"^(\d+)\s*(hours?|days?|weeks?|months?|years?|minutes?)$"#, in: body),
              let n = Int(capture(m, 1, in: body) ?? ""),
              let unit = capture(m, 2, in: body) else { return nil }
        return DurationMatch(value: n, component: durationComponent(for: unit))
    }

    private static func durationComponent(for unit: String) -> Calendar.Component {
        if unit.hasPrefix("hour") { return .hour }
        if unit.hasPrefix("minute") { return .minute }
        if unit.hasPrefix("week") { return .weekOfYear }
        if unit.hasPrefix("month") { return .month }
        if unit.hasPrefix("year") { return .year }
        return .day
    }

    // MARK: - Time suffix (tomorrow 5pm)

    private static func applyTimeSuffix(_ s: String, to base: Date, calendar: Calendar) -> Date? {
        let rest = s.replacingOccurrences(of: "tomorrow", with: "").trimmingCharacters(in: .whitespaces)
        guard !rest.isEmpty else { return nil }

        if rest == "noon" { return setTime(hour: 12, minute: 0, on: base, calendar: calendar) }
        if rest == "midnight" { return setTime(hour: 0, minute: 0, on: base, calendar: calendar) }

        if let m = firstMatch(#"^(\d{1,2})(?::(\d{2}))?\s*(am|pm)$"#, in: rest) {
            guard var hour = Int(capture(m, 1, in: rest) ?? "") else { return nil }
            let minute = Int(capture(m, 2, in: rest) ?? "") ?? 0
            let ampm = capture(m, 3, in: rest) ?? ""
            if ampm == "pm", hour < 12 { hour += 12 }
            if ampm == "am", hour == 12 { hour = 0 }
            return setTime(hour: hour, minute: minute, on: base, calendar: calendar)
        }
        return nil
    }

    // MARK: - Result

    private static func dateResult(_ date: Date) -> UtilityResult {
        UtilityResult(
            kind: .dateTime,
            copyText: UtilityFormatting.copyDateTime(date),
            previewText: UtilityFormatting.friendlyDateTime(date),
            detailText: UtilityFormatting.timezoneDetail()
        )
    }

    // MARK: - Calendar helpers

    private static func startOfToday(_ cal: Calendar) -> Date {
        cal.startOfDay(for: Date())
    }

    private static func nextWeekday(_ weekday: Int, after date: Date, calendar: Calendar) -> Date? {
        var comps = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear, .weekday], from: date)
        let current = comps.weekday ?? 1
        var days = weekday - current
        if days <= 0 { days += 7 }
        return calendar.date(byAdding: .day, value: days, to: calendar.startOfDay(for: date))
    }

    private static func setTime(hour: Int, minute: Int, on date: Date, calendar: Calendar) -> Date? {
        var comps = calendar.dateComponents([.year, .month, .day], from: date)
        comps.hour = hour
        comps.minute = minute
        comps.second = 0
        return calendar.date(from: comps)
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
