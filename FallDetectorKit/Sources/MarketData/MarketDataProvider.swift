import Foundation
import DetectorCore

public protocol MarketDataProvider: Sendable {
    var source: DataSource { get }
    func latestQuote(symbol: String) async throws -> Quote
    /// Daily closes, oldest first. May include the current (partial) session; callers drop it.
    func dailyHistory(symbol: String, tradingDays: Int) async throws -> [DailyBar]
}

public enum MarketDataError: LocalizedError, Equatable {
    case badStatus(Int)
    case noData(String)
    case api(String)
    case missingAPIKey

    public var errorDescription: String? {
        switch self {
        case .badStatus(let code): return "Data server returned HTTP \(code)."
        case .noData(let symbol): return "No data returned for \(symbol)."
        case .api(let message): return message
        case .missingAPIKey: return "An API key is required for this data source. Add it in Settings."
        }
    }
}

public enum ProviderFactory {
    public static func make(_ source: DataSource, apiKey: String?, session: URLSession = .shared) -> MarketDataProvider {
        switch source {
        case .yahoo: return YahooFinanceProvider(session: session)
        case .twelveData: return TwelveDataProvider(apiKey: apiKey ?? "", session: session)
        case .mock: return MockMarketDataProvider()
        }
    }
}

enum HTTP {
    static func get(_ url: URL, session: URLSession) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw MarketDataError.badStatus(http.statusCode)
        }
        return data
    }
}
