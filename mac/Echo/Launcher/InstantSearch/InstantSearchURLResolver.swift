import Foundation

enum InstantSearchURLResolver {
    /// Direct URL for domain-like queries; otherwise a Google results page.
    static func targetURL(for query: String, isDomainQuery: Bool) -> URL? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if isDomainQuery {
            var raw = trimmed
            if !raw.hasPrefix("http://"), !raw.hasPrefix("https://") {
                raw = "https://" + raw
            }
            return URL(string: raw)
        }

        guard let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            return nil
        }
        return URL(string: "https://www.google.com/search?q=\(encoded)")
    }

    static func displayHost(for query: String, isDomainQuery: Bool) -> String {
        if isDomainQuery, let url = targetURL(for: query, isDomainQuery: true), let host = url.host {
            return host
        }
        return "google.com"
    }
}
