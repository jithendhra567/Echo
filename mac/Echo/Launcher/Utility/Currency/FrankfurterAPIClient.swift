import Foundation
import os

enum FrankfurterAPIClient: Sendable {

    private nonisolated(unsafe) static let log = Logger(subsystem: "com.echo", category: "ExchangeRates")
    private nonisolated(unsafe) static let baseURL = URL(string: "https://api.frankfurter.app")!

    struct LatestResponse: Sendable {
        let amount: Double
        let base: String
        let date: String
        let rates: [String: Double]
    }

    enum ClientError: Error, LocalizedError {
        case invalidURL
        case badStatus(Int)
        case decodeFailed
        case offline

        var errorDescription: String? {
            switch self {
            case .invalidURL: return "Invalid currency API URL."
            case .badStatus(let c): return "Currency API error (\(c))."
            case .decodeFailed: return "Could not read exchange rates."
            case .offline: return "No network connection."
            }
        }
    }

    /// Fetches latest rates for `base`. If `targets` is non-empty, limits response to those codes.
    nonisolated static func fetchLatest(base: String, targets: [String] = []) async throws -> LatestResponse {
        var components = URLComponents(url: baseURL.appendingPathComponent("latest"), resolvingAgainstBaseURL: false)!
        var items = [URLQueryItem(name: "from", value: base.uppercased())]
        if !targets.isEmpty {
            items.append(URLQueryItem(name: "to", value: targets.map { $0.uppercased() }.joined(separator: ",")))
        }
        components.queryItems = items
        guard let url = components.url else { throw ClientError.invalidURL }

        log.info("Fetching exchange rates base=\(base, privacy: .public)")

        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.cachePolicy = .reloadIgnoringLocalCacheData

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            log.error("Network error: \(error.localizedDescription, privacy: .public)")
            throw ClientError.offline
        }

        guard let http = response as? HTTPURLResponse else { throw ClientError.badStatus(-1) }
        guard (200...299).contains(http.statusCode) else {
            log.error("HTTP \(http.statusCode)")
            throw ClientError.badStatus(http.statusCode)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let amount = json["amount"] as? Double,
              let base = json["base"] as? String,
              let date = json["date"] as? String,
              let rates = json["rates"] as? [String: Double] else {
            log.error("Decode failed: unexpected JSON shape")
            throw ClientError.decodeFailed
        }

        let decoded = LatestResponse(amount: amount, base: base, date: date, rates: rates)
        log.info("Received \(decoded.rates.count) rates for \(decoded.base, privacy: .public)")
        return decoded
    }
}
