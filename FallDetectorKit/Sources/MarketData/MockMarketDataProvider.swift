import Foundation
import DetectorCore

/// Deterministic offline data for demos, previews and tests.
/// Each symbol gets a smooth synthetic history and the current price is `todayChangePercent` off the last close.
public struct MockMarketDataProvider: MarketDataProvider {
    public let source = DataSource.mock
    public var todayChangePercent: Double
    private let calendar: MarketCalendar
    private let now: @Sendable () -> Date

    public init(todayChangePercent: Double = -2.5, calendar: MarketCalendar = .nyse,
                now: @escaping @Sendable () -> Date = { Date() }) {
        self.todayChangePercent = todayChangePercent
        self.calendar = calendar
        self.now = now
    }

    public func latestQuote(symbol: String) async throws -> Quote {
        let last = Self.series(symbol: symbol, count: Self.length).last ?? 100
        return Quote(price: last * (1 + todayChangePercent / 100), time: now())
    }

    public func dailyHistory(symbol: String, tradingDays: Int) async throws -> [DailyBar] {
        let days = calendar.tradingDays(before: now(), count: min(tradingDays + 5, Self.length))
        let closes = Self.series(symbol: symbol, count: Self.length).suffix(days.count)
        return zip(days, closes).map { DailyBar(day: calendar.dayKey(for: $0), close: $1) }
    }

    static let length = 300

    /// Closes ending at a fixed level, with a rally followed by a pullback in the last few months.
    static func series(symbol: String, count: Int) -> [Double] {
        let hash = symbol.unicodeScalars.reduce(5381) { ($0 &* 33 &+ Int($1.value)) & 0xFFFF }
        let seed = Double(hash % 97)
        let base = 1_000 + seed * 150
        var values: [Double] = []
        var level = base
        for i in 0..<max(count, 1) {
            let back = Double(count - 1 - i)  // days before the last bar
            let r = 0.0005 + 0.008 * sin(Double(i) * 0.9 + seed) * cos(Double(i) * 0.17)
            let pullback = back < 40 ? -0.0016 : 0
            level *= 1 + r + pullback
            values.append(level)
        }
        return values
    }
}
