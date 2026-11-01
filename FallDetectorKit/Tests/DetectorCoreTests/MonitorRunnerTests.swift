import XCTest
import DetectorCore
@testable import MarketData

struct FailingProvider: MarketDataProvider {
    let source = DataSource.mock
    func latestQuote(symbol: String) async throws -> Quote { throw MarketDataError.noData(symbol) }
    func dailyHistory(symbol: String, tradingDays: Int) async throws -> [DailyBar] { throw MarketDataError.noData(symbol) }
}

final class MonitorRunnerTests: XCTestCase {
    static let allTests: [(String, (MonitorRunnerTests) -> () async throws -> Void)] = [
        ("testAlertsOnceDuringSession", testAlertsOnceDuringSession),
        ("testSkipsWhenClosedUnlessForced", testSkipsWhenClosedUnlessForced),
        ("testFailureKeepsPreviousStatusAsStale", testFailureKeepsPreviousStatusAsStale),
        ("testStatePersistsAcrossRunnerInstances", testStatePersistsAcrossRunnerInstances),
    ]

    var dir: URL!
    let session = ny(2026, 10, 29, 11, 0)   // Thursday, market open

    override func setUp() {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("runner-tests-\(UUID().uuidString)")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: dir)
    }

    func makeRunner(change: Double = -2.5, at now: Date) -> MonitorRunner {
        MonitorRunner(directory: dir) { _ in MockMarketDataProvider(todayChangePercent: change, now: { now }) }
    }

    func testAlertsOnceDuringSession() async {
        let runner = makeRunner(at: session)
        let first = await runner.run(settings: .default, now: session)
        XCTAssertTrue(first.alertsEvaluated)
        XCTAssertEqual(first.statuses.map(\.index.id), ["sp500", "dow", "nasdaq"])
        XCTAssertEqual(first.newAlerts.filter { $0.kind == .daily }.count, 3)
        let second = await runner.run(settings: .default, now: session.addingTimeInterval(900))
        XCTAssertTrue(second.newAlerts.isEmpty)
        let history = await runner.history()
        XCTAssertEqual(history.count, first.newAlerts.count)
    }

    func testSkipsWhenClosedUnlessForced() async {
        let saturday = ny(2026, 10, 31, 11, 0)
        let runner = makeRunner(at: saturday)
        let skipped = await runner.run(settings: .default, now: saturday)
        XCTAssertNotNil(skipped.skippedReason)
        XCTAssertTrue(skipped.statuses.isEmpty)
        let forced = await runner.run(settings: .default, now: saturday, force: true)
        XCTAssertNil(forced.skippedReason)
        XCTAssertEqual(forced.statuses.count, 3)
        XCTAssertFalse(forced.alertsEvaluated)
        XCTAssertTrue(forced.newAlerts.isEmpty)
    }

    func testFailureKeepsPreviousStatusAsStale() async {
        _ = await makeRunner(at: session).run(settings: .default, now: session)
        let failing = MonitorRunner(directory: dir) { _ in FailingProvider() }
        let result = await failing.run(settings: .default, now: session.addingTimeInterval(900))
        XCTAssertEqual(result.errors.count, 3)
        XCTAssertEqual(result.statuses.count, 3)
        XCTAssertTrue(result.statuses.allSatisfy(\.isStale))
        XCTAssertTrue(result.newAlerts.isEmpty)
    }

    func testStatePersistsAcrossRunnerInstances() async {
        let first = await makeRunner(at: session).run(settings: .default, now: session)
        XCTAssertFalse(first.newAlerts.isEmpty)
        // A fresh runner (e.g. after the app was killed) must not repeat the alerts.
        let again = await makeRunner(at: session).run(settings: .default, now: session.addingTimeInterval(900))
        XCTAssertTrue(again.newAlerts.isEmpty)
        let last = await makeRunner(at: session).lastResult()
        XCTAssertNotNil(last)
    }
}
