import Foundation

// MARK: - Detectors

public enum DetectorKind: String, Codable, CaseIterable, Identifiable, Sendable, CodingKeyRepresentable {
    case daily, threeMonth, sixMonth, oneYear

    public var id: String { rawValue }

    /// Trailing window in trading days; `nil` for the daily detector.
    public var windowTradingDays: Int? {
        switch self {
        case .daily: return nil
        case .threeMonth: return 63
        case .sixMonth: return 126
        case .oneYear: return 252
        }
    }

    public var title: String {
        switch self {
        case .daily: return "Daily Fall"
        case .threeMonth: return "3-Month Drop"
        case .sixMonth: return "6-Month Drop"
        case .oneYear: return "1-Year Drop"
        }
    }

    /// Short label used on the dashboard rows.
    public var shortLabel: String {
        switch self {
        case .daily: return "Today"
        case .threeMonth: return "vs 3M high"
        case .sixMonth: return "vs 6M high"
        case .oneYear: return "vs 1Y high"
        }
    }

    /// Used in sentences: "below 6-month high".
    public var windowName: String {
        switch self {
        case .daily: return "previous close"
        case .threeMonth: return "3-month"
        case .sixMonth: return "6-month"
        case .oneYear: return "1-year"
        }
    }

    public var explanation: String {
        switch self {
        case .daily: return "Drop since the previous trading day's close."
        case .threeMonth: return "Drop from the highest close of the last 3 months."
        case .sixMonth: return "Drop from the highest close of the last 6 months."
        case .oneYear: return "Drop from the highest close of the last 12 months."
        }
    }

    public var defaultThreshold: Double {
        switch self {
        case .daily: return 2.0
        case .threeMonth: return 7.0
        case .sixMonth: return 10.0
        case .oneYear: return 15.0
        }
    }

    public var isEnabledByDefault: Bool { self != .oneYear }
}

public struct DetectorConfig: Codable, Equatable, Sendable {
    public var isEnabled: Bool
    /// Percent, as a positive number (2.0 means "down 2%").
    public var threshold: Double

    public init(isEnabled: Bool, threshold: Double) {
        self.isEnabled = isEnabled
        self.threshold = threshold
    }
}

// MARK: - Data source

public enum DataSource: String, Codable, CaseIterable, Identifiable, Sendable {
    case yahoo, twelveData, mock

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .yahoo: return "Yahoo Finance (free, no key)"
        case .twelveData: return "Twelve Data (API key)"
        case .mock: return "Demo data (offline)"
        }
    }

    public var requiresAPIKey: Bool { self == .twelveData }
}

// MARK: - Indices

public struct MarketIndex: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var yahooSymbol: String
    public var twelveDataSymbol: String
    public var etfSymbol: String
    public var isDefault: Bool

    public func symbol(for source: DataSource, useETF: Bool) -> String {
        if useETF { return etfSymbol }
        switch source {
        case .yahoo, .mock: return yahooSymbol
        case .twelveData: return twelveDataSymbol
        }
    }

    public static let sp500 = MarketIndex(id: "sp500", name: "S&P 500", yahooSymbol: "^GSPC", twelveDataSymbol: "SPX", etfSymbol: "SPY", isDefault: true)
    public static let dow = MarketIndex(id: "dow", name: "Dow Jones", yahooSymbol: "^DJI", twelveDataSymbol: "DJI", etfSymbol: "DIA", isDefault: true)
    public static let nasdaq = MarketIndex(id: "nasdaq", name: "Nasdaq Composite", yahooSymbol: "^IXIC", twelveDataSymbol: "IXIC", etfSymbol: "QQQ", isDefault: true)
    public static let russell2000 = MarketIndex(id: "russell2000", name: "Russell 2000", yahooSymbol: "^RUT", twelveDataSymbol: "RUT", etfSymbol: "IWM", isDefault: false)
    public static let totalMarket = MarketIndex(id: "totalMarket", name: "Total US Market", yahooSymbol: "^W5000", twelveDataSymbol: "W5000", etfSymbol: "VTI", isDefault: false)

    public static let all: [MarketIndex] = [.sp500, .dow, .nasdaq, .russell2000, .totalMarket]

    public static func with(id: String) -> MarketIndex? { all.first { $0.id == id } }
}

// MARK: - Settings

public struct MonitorSettings: Codable, Equatable, Sendable {
    public static let thresholdRange: ClosedRange<Double> = 0.1...50.0
    public static let allowedIntervals = [15, 30]

    public var detectors: [DetectorKind: DetectorConfig]
    public var intervalMinutes: Int
    public var marketHoursOnly: Bool
    public var watchedIndexIDs: [String]
    /// Re-alert when a breached drop deepens by this many percentage points.
    public var escalationStep: Double
    /// A breached detector re-arms once the drop recovers to `threshold - hysteresis`.
    public var hysteresis: Double
    public var useETFProxies: Bool
    public var dataSource: DataSource
    public var timeSensitiveAlerts: Bool
    public var snoozedUntil: Date?

    public static let `default` = MonitorSettings(
        detectors: Dictionary(uniqueKeysWithValues: DetectorKind.allCases.map {
            ($0, DetectorConfig(isEnabled: $0.isEnabledByDefault, threshold: $0.defaultThreshold))
        }),
        intervalMinutes: 15,
        marketHoursOnly: true,
        watchedIndexIDs: MarketIndex.all.filter(\.isDefault).map(\.id),
        escalationStep: 1.0,
        hysteresis: 1.0,
        useETFProxies: false,
        dataSource: .yahoo,
        timeSensitiveAlerts: true,
        snoozedUntil: nil
    )

    public init(detectors: [DetectorKind: DetectorConfig], intervalMinutes: Int, marketHoursOnly: Bool,
                watchedIndexIDs: [String], escalationStep: Double, hysteresis: Double, useETFProxies: Bool,
                dataSource: DataSource, timeSensitiveAlerts: Bool, snoozedUntil: Date?) {
        self.detectors = detectors
        self.intervalMinutes = intervalMinutes
        self.marketHoursOnly = marketHoursOnly
        self.watchedIndexIDs = watchedIndexIDs
        self.escalationStep = escalationStep
        self.hysteresis = hysteresis
        self.useETFProxies = useETFProxies
        self.dataSource = dataSource
        self.timeSensitiveAlerts = timeSensitiveAlerts
        self.snoozedUntil = snoozedUntil
    }

    private enum CodingKeys: String, CodingKey {
        case detectors, intervalMinutes, marketHoursOnly, watchedIndexIDs, escalationStep, hysteresis,
             useETFProxies, dataSource, timeSensitiveAlerts, snoozedUntil
    }

    /// Tolerant decoding: missing keys fall back to defaults so app updates never wipe settings.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = MonitorSettings.default
        detectors = (try? c.decodeIfPresent([DetectorKind: DetectorConfig].self, forKey: .detectors)) ?? d.detectors
        intervalMinutes = (try? c.decodeIfPresent(Int.self, forKey: .intervalMinutes)) ?? d.intervalMinutes
        marketHoursOnly = (try? c.decodeIfPresent(Bool.self, forKey: .marketHoursOnly)) ?? d.marketHoursOnly
        watchedIndexIDs = (try? c.decodeIfPresent([String].self, forKey: .watchedIndexIDs)) ?? d.watchedIndexIDs
        escalationStep = (try? c.decodeIfPresent(Double.self, forKey: .escalationStep)) ?? d.escalationStep
        hysteresis = (try? c.decodeIfPresent(Double.self, forKey: .hysteresis)) ?? d.hysteresis
        useETFProxies = (try? c.decodeIfPresent(Bool.self, forKey: .useETFProxies)) ?? d.useETFProxies
        dataSource = (try? c.decodeIfPresent(DataSource.self, forKey: .dataSource)) ?? d.dataSource
        timeSensitiveAlerts = (try? c.decodeIfPresent(Bool.self, forKey: .timeSensitiveAlerts)) ?? d.timeSensitiveAlerts
        snoozedUntil = try? c.decodeIfPresent(Date.self, forKey: .snoozedUntil)
    }

    public func config(for kind: DetectorKind) -> DetectorConfig {
        detectors[kind] ?? DetectorConfig(isEnabled: false, threshold: kind.defaultThreshold)
    }

    public var watchedIndices: [MarketIndex] {
        MarketIndex.all.filter { watchedIndexIDs.contains($0.id) }
    }

    /// Monitoring needs at least one enabled detector and one watched index.
    public var isMonitoringActive: Bool {
        detectors.values.contains(where: \.isEnabled) && !watchedIndices.isEmpty
    }

    public func isSnoozed(at date: Date) -> Bool {
        guard let until = snoozedUntil else { return false }
        return date < until
    }

    public static func clampThreshold(_ value: Double) -> Double {
        guard value.isFinite else { return thresholdRange.lowerBound }
        let rounded = (value * 10).rounded() / 10
        return min(max(rounded, thresholdRange.lowerBound), thresholdRange.upperBound)
    }

    /// Fills missing detectors and clamps every value into its valid range.
    public func normalized() -> MonitorSettings {
        var s = self
        for kind in DetectorKind.allCases {
            var cfg = s.detectors[kind] ?? MonitorSettings.default.config(for: kind)
            cfg.threshold = Self.clampThreshold(cfg.threshold)
            s.detectors[kind] = cfg
        }
        if !Self.allowedIntervals.contains(s.intervalMinutes) { s.intervalMinutes = 15 }
        s.watchedIndexIDs = MarketIndex.all.map(\.id).filter { s.watchedIndexIDs.contains($0) }
        s.escalationStep = min(max(s.escalationStep, 0.1), 10)
        s.hysteresis = min(max(s.hysteresis, 0), 10)
        return s
    }
}

// MARK: - Market data snapshots

public struct DailyBar: Codable, Equatable, Sendable {
    /// Trading day in New York time, "yyyy-MM-dd".
    public var day: String
    public var close: Double

    public init(day: String, close: Double) {
        self.day = day
        self.close = close
    }
}

public struct Quote: Codable, Equatable, Sendable {
    public var price: Double
    public var time: Date

    public init(price: Double, time: Date) {
        self.price = price
        self.time = time
    }
}

/// Everything the detector engine needs for one index at one moment.
public struct IndexSnapshot: Equatable, Sendable {
    public var index: MarketIndex
    public var price: Double
    public var quoteTime: Date
    public var previousClose: Double
    /// Completed sessions before the quote's session, oldest first.
    public var closes: [Double]

    public init(index: MarketIndex, price: Double, quoteTime: Date, previousClose: Double, closes: [Double]) {
        self.index = index
        self.price = price
        self.quoteTime = quoteTime
        self.previousClose = previousClose
        self.closes = closes
    }

    /// Builds a snapshot from a quote and daily bars. Bars from the quote's own session (or later)
    /// are dropped, so the previous close is always the last *completed* session.
    public static func make(index: MarketIndex, quote: Quote, bars: [DailyBar],
                            calendar: MarketCalendar = .nyse) -> IndexSnapshot? {
        let session = calendar.dayKey(for: quote.time)
        let completed = bars.filter { $0.day < session }.sorted { $0.day < $1.day }
        guard let previous = completed.last?.close, previous > 0, quote.price > 0 else { return nil }
        return IndexSnapshot(index: index, price: quote.price, quoteTime: quote.time,
                             previousClose: previous, closes: completed.map(\.close))
    }

    public var dailyChangePercent: Double { (price - previousClose) / previousClose * 100 }
}
