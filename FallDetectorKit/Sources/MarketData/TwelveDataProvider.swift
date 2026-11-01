import Foundation
import DetectorCore

/// Twelve Data REST API. The free plan covers US ETFs (turn on "Use ETF proxies");
/// index symbols such as SPX need a paid plan.
public struct TwelveDataProvider: MarketDataProvider {
    public let source = DataSource.twelveData
    private let apiKey: String
    private let session: URLSession

    public init(apiKey: String, session: URLSession = .shared) {
        self.apiKey = apiKey
        self.session = session
    }

    public func latestQuote(symbol: String) async throws -> Quote {
        let data = try await request("quote", ["symbol": symbol])
        let q = try JSONDecoder().decode(QuoteResponse.self, from: data)
        guard let price = q.close.flatMap(Double.init) else { throw MarketDataError.noData(symbol) }
        let time = q.timestamp.map { Date(timeIntervalSince1970: $0) } ?? Date()
        return Quote(price: price, time: time)
    }

    public func dailyHistory(symbol: String, tradingDays: Int) async throws -> [DailyBar] {
        let data = try await request("time_series", [
            "symbol": symbol, "interval": "1day", "outputsize": String(tradingDays + 5), "timezone": "America/New_York",
        ])
        let series = try JSONDecoder().decode(SeriesResponse.self, from: data)
        let bars = (series.values ?? []).compactMap { v -> DailyBar? in
            guard let close = Double(v.close), close > 0 else { return nil }
            return DailyBar(day: String(v.datetime.prefix(10)), close: close)
        }
        guard !bars.isEmpty else { throw MarketDataError.noData(symbol) }
        return bars.sorted { $0.day < $1.day }
    }

    private func request(_ endpoint: String, _ params: [String: String]) async throws -> Data {
        guard !apiKey.isEmpty else { throw MarketDataError.missingAPIKey }
        var components = URLComponents(string: "https://api.twelvedata.com/\(endpoint)")!
        components.queryItems = params.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
            + [URLQueryItem(name: "apikey", value: apiKey)]
        let data = try await HTTP.get(components.url!, session: session)
        if let err = try? JSONDecoder().decode(ErrorResponse.self, from: data), err.status == "error" {
            throw MarketDataError.api(err.message ?? "Twelve Data error")
        }
        return data
    }

    struct ErrorResponse: Decodable {
        let status: String?
        let message: String?
    }

    struct QuoteResponse: Decodable {
        let close: String?
        let timestamp: TimeInterval?
    }

    struct SeriesResponse: Decodable {
        let values: [Value]?

        struct Value: Decodable {
            let datetime: String
            let close: String
        }
    }
}
