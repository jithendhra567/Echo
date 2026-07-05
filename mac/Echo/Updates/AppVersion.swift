import Foundation

enum AppVersion {
    static var marketing: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    static var build: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
    }

    static var display: String {
        "\(marketing) (\(build))"
    }

    /// Compares dotted version strings numerically (e.g. 1.0.3 < 1.1.0).
    static func compare(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let a = components(lhs)
        let b = components(rhs)
        let count = max(a.count, b.count)
        for i in 0..<count {
            let left = i < a.count ? a[i] : 0
            let right = i < b.count ? b[i] : 0
            if left < right { return .orderedAscending }
            if left > right { return .orderedDescending }
        }
        return .orderedSame
    }

    static func isLessThan(_ version: String, than other: String) -> Bool {
        compare(version, other) == .orderedAscending
    }

    private static func components(_ version: String) -> [Int] {
        version
            .split(separator: ".", omittingEmptySubsequences: false)
            .map { Int($0.filter(\.isNumber)) ?? 0 }
    }
}
