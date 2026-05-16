import Foundation

enum UtilityFormatting {

    private static let friendlyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = .current
        f.timeZone = .current
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        f.timeZone = .current
        return f
    }()

    static func friendlyDateTime(_ date: Date) -> String {
        friendlyFormatter.string(from: date)
    }

    static func copyDateTime(_ date: Date) -> String {
        isoFormatter.string(from: date)
    }

    static func timezoneDetail() -> String {
        TimeZone.current.identifier
    }
}
