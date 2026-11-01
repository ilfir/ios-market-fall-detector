import Foundation

public enum MarketStatus: String, Codable, Sendable {
    case open, preMarket, afterHours, weekend, holiday

    public var title: String {
        switch self {
        case .open: return "Open"
        case .preMarket: return "Pre-market"
        case .afterHours: return "Closed"
        case .weekend: return "Weekend"
        case .holiday: return "Holiday"
        }
    }
}

public struct TradingSession: Equatable, Sendable {
    public var open: Date
    public var close: Date
}

/// NYSE trading hours in America/New_York, including holidays and early closes.
/// The holiday table must be extended every year (see `lastKnownYear`).
public struct MarketCalendar: Sendable {
    public static let nyse = MarketCalendar()

    public static let lastKnownYear = 2027

    public static let holidays: Set<String> = [
        // 2025
        "2025-01-01", "2025-01-09", "2025-01-20", "2025-02-17", "2025-04-18", "2025-05-26",
        "2025-06-19", "2025-07-04", "2025-09-01", "2025-11-27", "2025-12-25",
        // 2026
        "2026-01-01", "2026-01-19", "2026-02-16", "2026-04-03", "2026-05-25", "2026-06-19",
        "2026-07-03", "2026-09-07", "2026-11-26", "2026-12-25",
        // 2027
        "2027-01-01", "2027-01-18", "2027-02-15", "2027-03-26", "2027-05-31", "2027-06-18",
        "2027-07-05", "2027-09-06", "2027-11-25", "2027-12-24",
    ]

    /// 1:00 pm ET closes.
    public static let earlyCloses: Set<String> = [
        "2025-07-03", "2025-11-28", "2025-12-24",
        "2026-11-27", "2026-12-24",
        "2027-11-26",
    ]

    /// Extra check after the close so the final move of the day is caught.
    public static let postCloseCheckMinutes = 5
    /// How long after the close a scheduled (non-forced) check may still alert.
    public static let monitoringGraceMinutes = 10

    public let timeZone: TimeZone
    private let calendar: Calendar

    public init() {
        timeZone = TimeZone(identifier: "America/New_York")!
        var c = Calendar(identifier: .gregorian)
        c.timeZone = timeZone
        calendar = c
    }

    public func dayKey(for date: Date) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    public func isWeekend(_ date: Date) -> Bool {
        let weekday = calendar.component(.weekday, from: date)
        return weekday == 1 || weekday == 7
    }

    public func isTradingDay(_ date: Date) -> Bool {
        !isWeekend(date) && !Self.holidays.contains(dayKey(for: date))
    }

    public func session(on date: Date) -> TradingSession? {
        guard isTradingDay(date) else { return nil }
        let start = calendar.startOfDay(for: date)
        let closeHour = Self.earlyCloses.contains(dayKey(for: date)) ? 13 : 16
        guard let open = calendar.date(bySettingHour: 9, minute: 30, second: 0, of: start),
              let close = calendar.date(bySettingHour: closeHour, minute: 0, second: 0, of: start) else { return nil }
        return TradingSession(open: open, close: close)
    }

    public func status(at date: Date) -> MarketStatus {
        if isWeekend(date) { return .weekend }
        guard let s = session(on: date) else { return .holiday }
        if date < s.open { return .preMarket }
        if date < s.close { return .open }
        return .afterHours
    }

    /// Between the open and a few minutes after the close: scheduled checks may alert.
    public func isInMonitoringWindow(_ date: Date) -> Bool {
        guard let s = session(on: date) else { return false }
        return date >= s.open && date <= s.close.addingTimeInterval(Double(Self.monitoringGraceMinutes) * 60)
    }

    /// Check times for a day: the open, every `intervalMinutes` until the close, plus one post-close check.
    public func checkSlots(on date: Date, intervalMinutes: Int) -> [Date] {
        guard let s = session(on: date), intervalMinutes > 0 else { return [] }
        var slots: [Date] = []
        var t = s.open
        while t <= s.close {
            slots.append(t)
            t = t.addingTimeInterval(Double(intervalMinutes) * 60)
        }
        slots.append(s.close.addingTimeInterval(Double(Self.postCloseCheckMinutes) * 60))
        return slots
    }

    public func nextCheck(after date: Date, intervalMinutes: Int) -> Date {
        var day = calendar.startOfDay(for: date)
        for _ in 0..<15 {
            if let slot = checkSlots(on: day, intervalMinutes: intervalMinutes).first(where: { $0 > date }) {
                return slot
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return date.addingTimeInterval(Double(intervalMinutes) * 60)
    }

    /// Midnight ET of the following calendar day (used for "snooze today").
    public func startOfNextDay(after date: Date) -> Date {
        let start = calendar.startOfDay(for: date)
        return calendar.date(byAdding: .day, value: 1, to: start) ?? date.addingTimeInterval(86_400)
    }

    /// The `count` most recent trading days strictly before `date`, oldest first.
    public func tradingDays(before date: Date, count: Int) -> [Date] {
        var result: [Date] = []
        var day = calendar.startOfDay(for: date)
        var guardCounter = 0
        while result.count < count && guardCounter < count * 2 + 30 {
            guard let prev = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = prev
            if isTradingDay(day) { result.append(day) }
            guardCounter += 1
        }
        return result.reversed()
    }
}
