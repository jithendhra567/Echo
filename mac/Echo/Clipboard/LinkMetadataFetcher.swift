import AppKit
import Foundation

/// Fetches Open Graph / page metadata for copied link clips.
actor LinkMetadataFetcher {
    struct Metadata: Sendable {
        var title: String?
        var imageData: Data?
        var faviconData: Data?
    }

    private static let maxHTMLBytes = 512_000
    private static let maxImageBytes = 2_000_000
    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 8
        config.timeoutIntervalForResource = 12
        return URLSession(configuration: config)
    }()

    func fetch(for urlString: String) async -> Metadata {
        guard let pageURL = normalizedURL(from: urlString) else { return Metadata() }
        var meta = Metadata()

        if let html = await fetchHTML(url: pageURL) {
            meta.title = parseTitle(from: html)
            if let imageURL = parseImageURL(from: html, baseURL: pageURL) {
                meta.imageData = await downloadImage(url: imageURL)
            }
        }

        if let faviconURL = FaviconURL.google(for: pageURL, size: 64) {
            meta.faviconData = await downloadImage(url: faviconURL, maxBytes: 120_000)
        }

        return meta
    }

    // MARK: - Network

    private func fetchHTML(url: URL) async -> String? {
        var request = URLRequest(url: url)
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) Echo/1.0",
            forHTTPHeaderField: "User-Agent"
        )
        guard let (data, response) = try? await Self.session.data(for: request),
              let http = response as? HTTPURLResponse,
              (200...399).contains(http.statusCode),
              data.count <= Self.maxHTMLBytes,
              let html = String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .isoLatin1)
        else { return nil }
        return html
    }

    private func downloadImage(url: URL, maxBytes: Int = maxImageBytes) async -> Data? {
        var request = URLRequest(url: url)
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) Echo/1.0",
            forHTTPHeaderField: "User-Agent"
        )
        guard let (data, response) = try? await Self.session.data(for: request),
              let http = response as? HTTPURLResponse,
              (200...399).contains(http.statusCode),
              data.count <= maxBytes,
              !data.isEmpty
        else { return nil }
        return data
    }

    // MARK: - HTML parsing

    private func parseTitle(from html: String) -> String? {
        let patterns = [
            #"<meta[^>]+property=["']og:title["'][^>]+content=["']([^"']+)["']"#,
            #"<meta[^>]+content=["']([^"']+)["'][^>]+property=["']og:title["']"#,
            #"<meta[^>]+name=["']twitter:title["'][^>]+content=["']([^"']+)["']"#,
            #"<title[^>]*>([^<]+)</title>"#,
        ]
        for pattern in patterns {
            if let value = firstMatch(pattern, in: html, group: 1) {
                let decoded = decodeHTMLEntities(value.trimmingCharacters(in: .whitespacesAndNewlines))
                if !decoded.isEmpty { return decoded }
            }
        }
        return nil
    }

    private func parseImageURL(from html: String, baseURL: URL) -> URL? {
        let patterns = [
            #"<meta[^>]+property=["']og:image["'][^>]+content=["']([^"']+)["']"#,
            #"<meta[^>]+content=["']([^"']+)["'][^>]+property=["']og:image["']"#,
            #"<meta[^>]+name=["']twitter:image["'][^>]+content=["']([^"']+)["']"#,
        ]
        for pattern in patterns {
            if let raw = firstMatch(pattern, in: html, group: 1) {
                let decoded = decodeHTMLEntities(raw.trimmingCharacters(in: .whitespacesAndNewlines))
                if let url = URL(string: decoded, relativeTo: baseURL)?.absoluteURL {
                    return url
                }
            }
        }
        return nil
    }

    private func firstMatch(_ pattern: String, in text: String, group: Int) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
        else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              group < match.numberOfRanges,
              let swiftRange = Range(match.range(at: group), in: text)
        else { return nil }
        return String(text[swiftRange])
    }

    private func decodeHTMLEntities(_ string: String) -> String {
        guard let data = string.data(using: .utf8) else { return string }
        let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
            .documentType: NSAttributedString.DocumentType.html,
            .characterEncoding: String.Encoding.utf8.rawValue,
        ]
        guard let attributed = try? NSAttributedString(data: data, options: options, documentAttributes: nil)
        else { return string }
        return attributed.string
    }

    // MARK: - URL normalization

    private func normalizedURL(from urlString: String) -> URL? {
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
