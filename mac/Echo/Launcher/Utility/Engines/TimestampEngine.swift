import Foundation

enum TimestampEngine {

    private static let maxEpoch: TimeInterval = 4_102_444_800 // ~2100

    private static let nowPhrasesSec: Set<String> = [
        "unix now",
        "timestamp now",
        "unix timestamp now",
        "current unix timestamp",
        "unix timestamp",
    ]

    private static let nowPhrasesMs: Set<String> = [
        "milliseconds timestamp now",
        "millisecond timestamp now",
        "current milliseconds timestamp",
        "unix ms now",
    ]

    static func evaluate(_ norm: UtilityQueryNormalizer.NormalizedQuery) -> UtilityResult? {
        if let r = evaluateKeywords(norm) { return r }
        return evaluateLiteral(norm)
    }

    private static func evaluateKeywords(_ norm: UtilityQueryNormalizer.NormalizedQuery) -> UtilityResult? {
        let s = norm.lowercased
        let now = Date()

        if nowPhrasesMs.contains(s) {
            let ms = Int64(now.timeIntervalSince1970 * 1000)
            return makeResult(copyText: String(ms), date: now)
        }

        guard nowPhrasesSec.contains(s) else { return nil }
        let sec = Int64(now.timeIntervalSince1970)
        return makeResult(copyText: String(sec), date: now)
    }

    private static func evaluateLiteral(_ norm: UtilityQueryNormalizer.NormalizedQuery) -> UtilityResult? {
        let body = norm.hasLeadingEquals
            ? norm.expression.trimmingCharacters(in: .whitespaces)
            : norm.trimmed
        guard body.allSatisfy(\.isNumber) else { return nil }

        if body.count == 10, let sec = Double(body), sec <= maxEpoch {
            let date = Date(timeIntervalSince1970: sec)
            return makeResult(copyText: body, date: date)
        }
        if body.count == 13, let ms = Double(body) {
            let sec = ms / 1000
            guard sec <= maxEpoch else { return nil }
            let date = Date(timeIntervalSince1970: sec)
            return makeResult(copyText: body, date: date)
        }
        return nil
    }

    private static func makeResult(copyText: String, date: Date) -> UtilityResult {
        UtilityResult(
            kind: .timestamp,
            copyText: copyText,
            previewText: UtilityFormatting.friendlyDateTime(date),
            detailText: UtilityFormatting.timezoneDetail()
        )
    }
}
