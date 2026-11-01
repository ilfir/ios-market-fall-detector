import XCTest
@testable import DetectorCore

/// Builds a Date from New York wall-clock time.
func ny(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 12, _ min: Int = 0) -> Date {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "America/New_York")!
    return c.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
}

final class DetectorEngineTests: XCTestCase {
    static let allTests: [(String, (DetectorEngineTests) -> () async throws -> Void)] = [
        ("testDailyBreachAtExactThreshold", testDailyBreachAtExactThreshold),
        ("testDailyGainDoesNotBreach", testDailyGainDoesNotBreach),
        ("testDrawdownUsesWindowHigh", testDrawdownUsesWindowHigh),
        ("testPartialWindowFlag", testPartialWindowFlag),
        ("testDisabledDetectorIsEvaluatedButNotBreached", testDisabledDetectorIsEvaluatedButNotBreached),
        ("testSnapshotDropsCurrentSessionBar", testSnapshotDropsCurrentSessionBar),
        ("testImplausibleMoveRejected", testImplausibleMoveRejected),
    ]

    var settings = MonitorSettings.default

    override func setUp() {
        settings = MonitorSettings.default
        for kind in DetectorKind.allCases { settings.detectors[kind]?.isEnabled = true }
    }

    func snapshot(price: Double, prev: Double = 100, closes: [Double]? = nil) -> IndexSnapshot {
        IndexSnapshot(index: .sp500, price: price, quoteTime: Date(), previousClose: prev,
                      closes: closes ?? Array(repeating: prev, count: 260))
    }

    func eval(_ s: IndexSnapshot, _ kind: DetectorKind) -> DetectorEvaluation {
        DetectorEngine.evaluate(s, settings: settings).first { $0.kind == kind }!
    }

    func testDailyBreachAtExactThreshold() {
        let e = eval(snapshot(price: 98), .daily)  // -2.0%, threshold 2.0
        XCTAssertEqual(e.dropPercent, 2.0, accuracy: 1e-9)
        XCTAssertTrue(e.isBreached)
        XCTAssertFalse(eval(snapshot(price: 98.05), .daily).isBreached)
    }

    func testDailyGainDoesNotBreach() {
        let e = eval(snapshot(price: 103), .daily)
        XCTAssertEqual(e.changePercent, 3.0, accuracy: 1e-9)
        XCTAssertFalse(e.isBreached)
        XCTAssertFalse(e.isNearThreshold)
    }

    func testDrawdownUsesWindowHigh() {
        // A 1-year-old peak of 200 must not count for the 3M window.
        var closes = Array(repeating: 100.0, count: 260)
        closes[10] = 200          // ~250 sessions ago: inside 1Y only
        closes[200] = 110         // ~60 sessions ago: inside 3M
        let s = snapshot(price: 99, prev: 100, closes: closes)
        XCTAssertEqual(eval(s, .threeMonth).referencePrice, 110)
        XCTAssertEqual(eval(s, .threeMonth).dropPercent, 10.0, accuracy: 1e-9)
        XCTAssertTrue(eval(s, .threeMonth).isBreached)        // threshold 7
        XCTAssertEqual(eval(s, .sixMonth).referencePrice, 110)
        XCTAssertEqual(eval(s, .oneYear).referencePrice, 200)
        XCTAssertTrue(eval(s, .oneYear).isBreached)           // 50.5% >= 15
    }

    func testPartialWindowFlag() {
        let s = snapshot(price: 100, closes: Array(repeating: 100, count: 100))
        XCTAssertFalse(eval(s, .threeMonth).isPartialWindow)
        XCTAssertTrue(eval(s, .sixMonth).isPartialWindow)
        XCTAssertTrue(eval(s, .oneYear).isPartialWindow)
    }

    func testDisabledDetectorIsEvaluatedButNotBreached() {
        settings.detectors[.daily]?.isEnabled = false
        let e = eval(snapshot(price: 90), .daily)
        XCTAssertFalse(e.isEnabled)
        XCTAssertFalse(e.isBreached)
        XCTAssertEqual(e.dropPercent, 10, accuracy: 1e-9)
    }

    func testSnapshotDropsCurrentSessionBar() {
        let bars = [DailyBar(day: "2026-10-28", close: 100), DailyBar(day: "2026-10-29", close: 102),
                    DailyBar(day: "2026-10-30", close: 97)]   // today's partial bar
        let quote = Quote(price: 97, time: ny(2026, 10, 30, 11))
        let s = IndexSnapshot.make(index: .sp500, quote: quote, bars: bars)!
        XCTAssertEqual(s.previousClose, 102)
        XCTAssertEqual(s.closes, [100, 102])
        // Weekend: the quote is Friday's close, so "today" is still Friday's move.
        let weekend = IndexSnapshot.make(index: .sp500, quote: Quote(price: 97, time: ny(2026, 10, 30, 16, 30)), bars: bars)!
        XCTAssertEqual(weekend.previousClose, 102)
    }

    func testImplausibleMoveRejected() {
        XCTAssertFalse(DetectorEngine.isPlausible(snapshot(price: 50)))
        XCTAssertTrue(DetectorEngine.isPlausible(snapshot(price: 88)))
    }
}

final class AlertDeduplicatorTests: XCTestCase {
    static let allTests: [(String, (AlertDeduplicatorTests) -> () async throws -> Void)] = [
        ("testFiresOnceThenSilent", testFiresOnceThenSilent),
        ("testEscalationStep", testEscalationStep),
        ("testDailyRearmsNextSession", testDailyRearmsNextSession),
        ("testDrawdownPersistsAcrossDaysUntilRecovery", testDrawdownPersistsAcrossDaysUntilRecovery),
        ("testThresholdChangeResets", testThresholdChangeResets),
        ("testDisablingClearsState", testDisablingClearsState),
    ]

    let dedup = AlertDeduplicator(escalationStep: 1.0, hysteresis: 1.0)
    var states: [String: AlertState] = [:]

    override func setUp() { states = [:] }

    func e(_ kind: DetectorKind, drop: Double, threshold: Double = 2, enabled: Bool = true) -> DetectorEvaluation {
        DetectorEvaluation(indexID: "sp500", kind: kind, dropPercent: drop, threshold: threshold, referencePrice: 100,
                           price: 100 - drop, isEnabled: enabled, isBreached: enabled && drop >= threshold,
                           isPartialWindow: false)
    }

    func run(_ evals: [DetectorEvaluation], day: String = "2026-10-29") -> [AlertEvent] {
        dedup.process(evals, index: .sp500, sessionDay: day, states: &states, now: Date())
    }

    func testFiresOnceThenSilent() {
        XCTAssertEqual(run([e(.daily, drop: 2.1)]).count, 1)
        XCTAssertEqual(run([e(.daily, drop: 2.3)]).count, 0)
        XCTAssertEqual(run([e(.daily, drop: 2.0)]).count, 0)
    }

    func testEscalationStep() {
        XCTAssertEqual(run([e(.daily, drop: 2.1)]).count, 1)
        XCTAssertEqual(run([e(.daily, drop: 3.0)]).count, 0)
        let second = run([e(.daily, drop: 3.1)])
        XCTAssertEqual(second.count, 1)
        XCTAssertEqual(second.first?.isEscalation, true)
        XCTAssertEqual(run([e(.daily, drop: 4.0)]).count, 0)
        XCTAssertEqual(run([e(.daily, drop: 4.1)]).count, 1)
    }

    func testDailyRearmsNextSession() {
        XCTAssertEqual(run([e(.daily, drop: 2.5)], day: "2026-10-29").count, 1)
        XCTAssertEqual(run([e(.daily, drop: 2.5)], day: "2026-10-29").count, 0)
        let next = run([e(.daily, drop: 2.2)], day: "2026-10-30")
        XCTAssertEqual(next.count, 1)
        XCTAssertEqual(next.first?.isEscalation, false)
    }

    func testDrawdownPersistsAcrossDaysUntilRecovery() {
        XCTAssertEqual(run([e(.threeMonth, drop: 7.5, threshold: 7)], day: "2026-10-28").count, 1)
        XCTAssertEqual(run([e(.threeMonth, drop: 7.8, threshold: 7)], day: "2026-10-29").count, 0)
        // Recovers just under the threshold but within hysteresis: still disarmed.
        XCTAssertEqual(run([e(.threeMonth, drop: 6.5, threshold: 7)], day: "2026-10-30").count, 0)
        XCTAssertEqual(run([e(.threeMonth, drop: 7.2, threshold: 7)], day: "2026-11-02").count, 0)
        // Recovers past threshold - hysteresis: re-arms, so the next breach alerts.
        XCTAssertEqual(run([e(.threeMonth, drop: 5.5, threshold: 7)], day: "2026-11-03").count, 0)
        XCTAssertEqual(run([e(.threeMonth, drop: 7.1, threshold: 7)], day: "2026-11-04").count, 1)
    }

    func testThresholdChangeResets() {
        XCTAssertEqual(run([e(.daily, drop: 2.5, threshold: 2)]).count, 1)
        XCTAssertEqual(run([e(.daily, drop: 2.5, threshold: 2.5)]).count, 1)
    }

    func testDisablingClearsState() {
        XCTAssertEqual(run([e(.daily, drop: 2.5)]).count, 1)
        XCTAssertEqual(run([e(.daily, drop: 2.5, enabled: false)]).count, 0)
        XCTAssertNil(states[AlertDeduplicator.key(indexID: "sp500", kind: .daily)])
        XCTAssertEqual(run([e(.daily, drop: 2.5)]).count, 1)
    }
}

final class MarketCalendarTests: XCTestCase {
    static let allTests: [(String, (MarketCalendarTests) -> () async throws -> Void)] = [
        ("testStatus", testStatus),
        ("testSlots", testSlots),
        ("testNextCheck", testNextCheck),
        ("testDaylightSavingTransition", testDaylightSavingTransition),
        ("testTradingDaysBefore", testTradingDaysBefore),
    ]

    let cal = MarketCalendar.nyse

    func testStatus() {
        XCTAssertEqual(cal.status(at: ny(2026, 10, 30, 9, 0)), .preMarket)
        XCTAssertEqual(cal.status(at: ny(2026, 10, 30, 9, 30)), .open)
        XCTAssertEqual(cal.status(at: ny(2026, 10, 30, 16, 0)), .afterHours)
        XCTAssertEqual(cal.status(at: ny(2026, 10, 31)), .weekend)
        XCTAssertEqual(cal.status(at: ny(2026, 11, 26)), .holiday)          // Thanksgiving
        XCTAssertEqual(cal.status(at: ny(2026, 11, 27, 13, 30)), .afterHours) // early close
        XCTAssertTrue(cal.isInMonitoringWindow(ny(2026, 10, 30, 16, 5)))
        XCTAssertFalse(cal.isInMonitoringWindow(ny(2026, 10, 30, 16, 30)))
    }

    func testSlots() {
        let s15 = cal.checkSlots(on: ny(2026, 10, 30), intervalMinutes: 15)
        XCTAssertEqual(s15.count, 28)   // 9:30...16:00 every 15 min (27) + 16:05
        XCTAssertEqual(s15.first, ny(2026, 10, 30, 9, 30))
        XCTAssertEqual(s15.last, ny(2026, 10, 30, 16, 5))
        XCTAssertEqual(cal.checkSlots(on: ny(2026, 10, 30), intervalMinutes: 30).count, 15)
        let early = cal.checkSlots(on: ny(2026, 11, 27), intervalMinutes: 30)
        XCTAssertEqual(early.last, ny(2026, 11, 27, 13, 5))
        XCTAssertTrue(cal.checkSlots(on: ny(2026, 10, 31), intervalMinutes: 15).isEmpty)
    }

    func testNextCheck() {
        XCTAssertEqual(cal.nextCheck(after: ny(2026, 10, 29, 10, 7), intervalMinutes: 15), ny(2026, 10, 29, 10, 15))
        XCTAssertEqual(cal.nextCheck(after: ny(2026, 10, 29, 10, 7), intervalMinutes: 30), ny(2026, 10, 29, 10, 30))
        XCTAssertEqual(cal.nextCheck(after: ny(2026, 10, 29, 16, 0), intervalMinutes: 15), ny(2026, 10, 29, 16, 5))
        XCTAssertEqual(cal.nextCheck(after: ny(2026, 10, 30, 17, 0), intervalMinutes: 15), ny(2026, 11, 2, 9, 30))
        XCTAssertEqual(cal.nextCheck(after: ny(2026, 11, 25, 17, 0), intervalMinutes: 15), ny(2026, 11, 27, 9, 30))
    }

    func testDaylightSavingTransition() {
        // DST ends 2026-11-01: the open moves from 13:30 UTC to 14:30 UTC.
        let utc = TimeZone(identifier: "UTC")!
        var c = Calendar(identifier: .gregorian)
        c.timeZone = utc
        XCTAssertEqual(c.component(.hour, from: cal.session(on: ny(2026, 10, 30))!.open), 13)
        XCTAssertEqual(c.component(.hour, from: cal.session(on: ny(2026, 11, 2))!.open), 14)
    }

    func testTradingDaysBefore() {
        let days = cal.tradingDays(before: ny(2026, 11, 30), count: 3).map(cal.dayKey)
        XCTAssertEqual(days, ["2026-11-24", "2026-11-25", "2026-11-27"])
    }
}

final class SettingsAndFormatterTests: XCTestCase {
    static let allTests: [(String, (SettingsAndFormatterTests) -> () async throws -> Void)] = [
        ("testSettingsRoundTrip", testSettingsRoundTrip),
        ("testSettingsDecodeWithMissingKeys", testSettingsDecodeWithMissingKeys),
        ("testNormalizedClamps", testNormalizedClamps),
        ("testMonitoringActive", testMonitoringActive),
        ("testSingleNotification", testSingleNotification),
        ("testGroupedNotification", testGroupedNotification),
    ]

    func testSettingsRoundTrip() throws {
        var s = MonitorSettings.default
        s.detectors[.sixMonth] = DetectorConfig(isEnabled: false, threshold: 12.5)
        s.intervalMinutes = 30
        let decoded = try JSONDecoder().decode(MonitorSettings.self, from: JSONEncoder().encode(s))
        XCTAssertEqual(decoded, s)
    }

    func testSettingsDecodeWithMissingKeys() throws {
        let json = #"{"intervalMinutes":30,"detectors":{"daily":{"isEnabled":false,"threshold":3}}}"#
        let s = try JSONDecoder().decode(MonitorSettings.self, from: Data(json.utf8)).normalized()
        XCTAssertEqual(s.intervalMinutes, 30)
        XCTAssertEqual(s.config(for: .daily), DetectorConfig(isEnabled: false, threshold: 3))
        XCTAssertEqual(s.config(for: .oneYear).threshold, 15)
        XCTAssertEqual(s.watchedIndexIDs, ["sp500", "dow", "nasdaq"])
    }

    func testNormalizedClamps() {
        var s = MonitorSettings.default
        s.detectors[.daily]?.threshold = 99
        s.detectors[.threeMonth]?.threshold = -1
        s.intervalMinutes = 7
        s.watchedIndexIDs = ["nasdaq", "bogus", "sp500"]
        let n = s.normalized()
        XCTAssertEqual(n.config(for: .daily).threshold, 50)
        XCTAssertEqual(n.config(for: .threeMonth).threshold, 0.1)
        XCTAssertEqual(n.intervalMinutes, 15)
        XCTAssertEqual(n.watchedIndexIDs, ["sp500", "nasdaq"])
    }

    func testMonitoringActive() {
        var s = MonitorSettings.default
        XCTAssertTrue(s.isMonitoringActive)
        s.watchedIndexIDs = []
        XCTAssertFalse(s.isMonitoringActive)
        s = .default
        for k in DetectorKind.allCases { s.detectors[k]?.isEnabled = false }
        XCTAssertFalse(s.isMonitoringActive)
    }

    func event(_ index: MarketIndex, _ kind: DetectorKind, _ drop: Double, ref: Double = 100) -> AlertEvent {
        AlertEvent(timestamp: Date(), indexID: index.id, indexName: index.name, kind: kind, dropPercent: drop,
                   threshold: kind.defaultThreshold, referencePrice: ref, price: ref * (1 - drop / 100), isEscalation: false)
    }

    func testSingleNotification() {
        let n = AlertFormatter.notification(for: [event(.sp500, .daily, 2.4, ref: 5750.15)])!
        XCTAssertEqual(n.title, "📉 S&P 500 down 2.4% today")
        XCTAssertTrue(n.body.hasPrefix("5,612.15 (\u{2212}138.00)"), n.body)
        let d = AlertFormatter.notification(for: [event(.nasdaq, .sixMonth, 10.3)])!
        XCTAssertEqual(d.title, "📉 Nasdaq Composite 10.3% below 6-month high")
    }

    func testGroupedNotification() {
        let n = AlertFormatter.notification(for: [
            event(.sp500, .daily, 2.4), event(.sp500, .threeMonth, 7.8), event(.dow, .daily, 2.1),
        ])!
        XCTAssertEqual(n.title, "📉 Market drop alert (3 triggers)")
        XCTAssertEqual(n.body, "S&P 500: \u{2212}2.4% today, \u{2212}7.8% vs 3M high · Dow Jones: \u{2212}2.1% today")
        XCTAssertNil(AlertFormatter.notification(for: []))
    }
}
