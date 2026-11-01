import Foundation
import DetectorCore

/// Uses Yahoo's public chart endpoint. Free and keyless but unofficial (no SLA); fine for personal use.
public struct YahooFinanceProvider: MarketDataProvider {
    public let source = DataSource.yahoo
    private let session: URLSession
    private let calendar: MarketCalendar

    public init(session: URLSession = .shared, calendar: MarketCalendar = .nyse) {
        self.session = session
        self.calendar = calendar
    }

    public func latestQuote(symbol: String) async throws -> Quote {
        let result = try await chart(symbol: symbol, range: "1d", interval: "1d")
        guard let price = result.meta.regularMarketPrice, let time = result.meta.regularMarketTime else {
            throw MarketDataError.noData(symbol)
        }
        return Quote(price: price, time: Date(timeIntervalSince1970: time))
    }

    public func dailyHistory(symbol: String, tradingDays: Int) async throws -> [DailyBar] {
        let result = try await chart(symbol: symbol, range: "2y", interval: "1d")
        let stamps = result.timestamp ?? []
        let closes = result.indicators.quote.first?.close ?? []
        var byDay: [String: Double] = [:]
        for (stamp, close) in zip(stamps, closes) {
            guard let close = close, close > 0 else { continue }
            byDay[calendar.dayKey(for: Date(timeIntervalSince1970: stamp))] = close
        }
        guard !byDay.isEmpty else { throw MarketDataError.noData(symbol) }
        let bars = byDay.map { DailyBar(day: $0.key, close: $0.value) }.sorted { $0.day < $1.day }
        return Array(bars.suffix(tradingDays + 5))
    }

    private func chart(symbol: String, range: String, interval: String) async throws -> YahooChart.Result {
        let path = symbol.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? symbol
        var components = URLComponents(string: "https://query1.finance.yahoo.com/v8/finance/chart/\(path)")!
        components.percentEncodedPath = "/v8/finance/chart/\(path)"
        components.queryItems = [
            URLQueryItem(name: "range", value: range),
            URLQueryItem(name: "interval", value: interval),
            URLQueryItem(name: "includePrePost", value: "false"),
        ]
        let data = try await HTTP.get(components.url!, session: session)
        let response = try JSONDecoder().decode(YahooChart.self, from: data)
        if let error = response.chart.error {
            throw MarketDataError.api(error.description ?? error.code ?? "Yahoo error")
        }
        guard let result = response.chart.result?.first else { throw MarketDataError.noData(symbol) }
        return result
    }
}

struct YahooChart: Decodable {
    let chart: Chart

    struct Chart: Decodable {
        let result: [Result]?
        let error: APIError?
    }

    struct APIError: Decodable {
        let code: String?
        let description: String?
    }

    struct Result: Decodable {
        let meta: Meta
        let timestamp: [TimeInterval]?
        let indicators: Indicators
    }

    struct Meta: Decodable {
        let symbol: String?
        let regularMarketPrice: Double?
        let regularMarketTime: TimeInterval?
    }

    struct Indicators: Decodable {
        let quote: [Series]
    }

    struct Series: Decodable {
        let close: [Double?]?
    }
}
