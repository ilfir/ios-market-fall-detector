import Foundation
import DetectorCore

public struct IndexStatus: Codable, Identifiable, Sendable {
    public var id: String { index.id }
    public var index: MarketIndex
    public var symbol: String
    public var price: Double
    public var previousClose: Double
    public var quoteTime: Date
    public var evaluations: [DetectorEvaluation]
    /// Last ~3 months of closes plus the current price, for the sparkline.
    public var recentCloses: [Double]
    /// Data too old to alert on (or carried over after a failed fetch).
    public var isStale: Bool

    public var dailyChangePercent: Double { (price - previousClose) / previousClose * 100 }

    public func evaluation(_ kind: DetectorKind) -> DetectorEvaluation? {
        evaluations.first { $0.kind == kind }
    }
}

public struct CheckResult: Codable, Sendable {
    public var checkedAt: Date
    public var marketStatus: MarketStatus
    public var statuses: [IndexStatus]
    public var newAlerts: [AlertEvent]
    /// Index ID -> error message.
    public var errors: [String: String]
    /// Set when the check was skipped (e.g. market closed); statuses are then from the previous check.
    public var skippedReason: String?
    /// False when the check ran outside the monitoring window, so alerts were not evaluated.
    public var alertsEvaluated: Bool
}

/// Runs one monitoring cycle: fetch → evaluate → dedupe → persist. Notifications are left to the caller.
public actor MonitorRunner {
    public typealias MakeProvider = @Sendable (MonitorSettings) -> MarketDataProvider

    public static let historyRetentionDays = 90
    public static let maxHistoryItems = 500

    private let calendar: MarketCalendar
    private let makeProvider: MakeProvider
    private let statesFile: JSONFile<[String: AlertState]>
    private let historyFile: JSONFile<[AlertEvent]>
    private let lastResultFile: JSONFile<CheckResult>
    private let barsFile: JSONFile<[String: CachedBars]>

    private var alertStates: [String: AlertState]
    private var alertHistory: [AlertEvent]
    private var last: CheckResult?
    private var barsCache: [String: CachedBars]

    struct CachedBars: Codable {
        var fetchedDay: String
        var bars: [DailyBar]
    }

    public init(directory: URL, calendar: MarketCalendar = .nyse, makeProvider: @escaping MakeProvider) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        self.calendar = calendar
        self.makeProvider = makeProvider
        statesFile = JSONFile(url: directory.appendingPathComponent("alert-states.json"))
        historyFile = JSONFile(url: directory.appendingPathComponent("alert-history.json"))
        lastResultFile = JSONFile(url: directory.appendingPathComponent("last-result.json"))
        barsFile = JSONFile(url: directory.appendingPathComponent("history-cache.json"))
        alertStates = statesFile.load() ?? [:]
        alertHistory = historyFile.load() ?? []
        last = lastResultFile.load()
        barsCache = barsFile.load() ?? [:]
    }

    public func lastResult() -> CheckResult? { last }
    public func history() -> [AlertEvent] { alertHistory }

    public func clearHistory() {
        alertHistory = []
        historyFile.save(alertHistory)
    }

    public func resetAlertStates() {
        alertStates = [:]
        statesFile.save(alertStates)
    }

    /// - Parameter force: run even when the market is closed (manual refresh). Alerts are only
    ///   evaluated inside the monitoring window, unless `marketHoursOnly` is off.
    public func run(settings raw: MonitorSettings, now: Date = Date(), force: Bool = false) async -> CheckResult {
        let settings = raw.normalized()
        let marketStatus = calendar.status(at: now)
        let inWindow = calendar.isInMonitoringWindow(now)

        if !force && settings.marketHoursOnly && !inWindow {
            var skipped = last ?? CheckResult(checkedAt: now, marketStatus: marketStatus, statuses: [], newAlerts: [],
                                              errors: [:], skippedReason: nil, alertsEvaluated: false)
            skipped.marketStatus = marketStatus
            skipped.newAlerts = []
            skipped.skippedReason = "Market closed (\(marketStatus.title.lowercased()))"
            return skipped
        }

        let provider = makeProvider(settings)
        let today = calendar.dayKey(for: now)
        let historyDays = DetectorKind.allCases.compactMap(\.windowTradingDays).max() ?? 252

        // Fetch all indices in parallel.
        typealias Fetched = (index: MarketIndex, symbol: String, result: Result<(Quote, [DailyBar], Bool), Error>)
        var fetched: [Fetched] = []
        await withTaskGroup(of: Fetched.self) { group in
            for index in settings.watchedIndices {
                let symbol = index.symbol(for: settings.dataSource, useETF: settings.useETFProxies)
                let cacheKey = "\(provider.source.rawValue)|\(symbol)"
                let cached = barsCache[cacheKey].flatMap { $0.fetchedDay == today ? $0.bars : nil }
                group.addTask {
                    do {
                        async let quote = provider.latestQuote(symbol: symbol)
                        if let cached = cached {
                            return (index, symbol, .success((try await quote, cached, false)))
                        }
                        let bars = try await provider.dailyHistory(symbol: symbol, tradingDays: historyDays)
                        return (index, symbol, .success((try await quote, bars, true)))
                    } catch {
                        return (index, symbol, .failure(error))
                    }
                }
            }
            for await item in group { fetched.append(item) }
        }

        var statuses: [IndexStatus] = []
        var errors: [String: String] = [:]
        let staleLimit = Double(max(settings.intervalMinutes * 2, 30) + 15) * 60

        for item in fetched {
            switch item.result {
            case .failure(let error):
                errors[item.index.id] = error.localizedDescription
                if var previous = last?.statuses.first(where: { $0.index.id == item.index.id }) {
                    previous.isStale = true
                    statuses.append(previous)
                }
            case .success(let (quote, bars, isFresh)):
                if isFresh {
                    barsCache["\(provider.source.rawValue)|\(item.symbol)"] = CachedBars(fetchedDay: today, bars: bars)
                }
                guard let snapshot = IndexSnapshot.make(index: item.index, quote: quote, bars: bars, calendar: calendar) else {
                    errors[item.index.id] = "Not enough price history for \(item.symbol)."
                    continue
                }
                guard DetectorEngine.isPlausible(snapshot) else {
                    errors[item.index.id] = "Ignored implausible move (\(AlertFormatter.signedPercent(snapshot.dailyChangePercent))) for \(item.symbol)."
                    continue
                }
                let isStale = marketStatus == .open && now.timeIntervalSince(quote.time) > staleLimit
                statuses.append(IndexStatus(
                    index: item.index, symbol: item.symbol, price: snapshot.price, previousClose: snapshot.previousClose,
                    quoteTime: quote.time, evaluations: DetectorEngine.evaluate(snapshot, settings: settings),
                    recentCloses: Array(snapshot.closes.suffix(63)) + [snapshot.price], isStale: isStale))
            }
        }
        let order = MarketIndex.all.map(\.id)
        statuses.sort { (order.firstIndex(of: $0.index.id) ?? 0) < (order.firstIndex(of: $1.index.id) ?? 0) }

        let alertsAllowed = inWindow || !settings.marketHoursOnly
        var newAlerts: [AlertEvent] = []
        if alertsAllowed {
            let dedup = AlertDeduplicator(settings: settings)
            for status in statuses where !status.isStale {
                newAlerts += dedup.process(status.evaluations, index: status.index,
                                           sessionDay: calendar.dayKey(for: status.quoteTime),
                                           states: &alertStates, now: now)
            }
            statesFile.save(alertStates)
        }

        if !newAlerts.isEmpty {
            let cutoff = now.addingTimeInterval(-Double(Self.historyRetentionDays) * 86_400)
            alertHistory = Array((newAlerts + alertHistory).filter { $0.timestamp >= cutoff }.prefix(Self.maxHistoryItems))
            historyFile.save(alertHistory)
        }

        let result = CheckResult(checkedAt: now, marketStatus: marketStatus, statuses: statuses, newAlerts: newAlerts,
                                 errors: errors, skippedReason: nil, alertsEvaluated: alertsAllowed)
        last = result
        lastResultFile.save(result)
        barsFile.save(barsCache)
        return result
    }
}

struct JSONFile<T: Codable>: Sendable {
    let url: URL

    func load() -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(T.self, from: data)
    }

    func save(_ value: T) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(value) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
