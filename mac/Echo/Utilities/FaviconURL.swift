import Foundation

enum FaviconURL {
    /// Resolves a favicon image URL for a page. Uses the full page URL so path-specific
    /// icons (e.g. Google Sheets vs Docs on docs.google.com) resolve correctly.
    nonisolated static func google(for pageURLString: String, size: Int = 32) -> URL? {
        guard let pageURL = normalizedPageURL(from: pageURLString) else { return nil }
        return google(for: pageURL, size: size)
    }

    nonisolated static func google(for pageURL: URL, size: Int = 32) -> URL? {
        var components = URLComponents(string: "https://t3.gstatic.com/faviconV2")
        components?.queryItems = [
            URLQueryItem(name: "client", value: "SOCIAL"),
            URLQueryItem(name: "type", value: "FAVICON"),
            URLQueryItem(name: "fallback_opts", value: "TYPE,SIZE,URL"),
            URLQueryItem(name: "url", value: pageURL.absoluteString),
            URLQueryItem(name: "size", value: String(size)),
        ]
        return components?.url
    }

    nonisolated private static func normalizedPageURL(from urlString: String) -> URL? {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: trimmed), url.scheme != nil, url.host != nil {
            return url
        }
        if let host = AppSettings.host(of: trimmed) {
            return URL(string: "https://\(host)")
        }
        return nil
    }
}
