import Foundation
import DetectorCore
import MarketData

// Usage: swift run fdk-check [--source yahoo|twelveData|mock] [--etf] [--all] [--key API_KEY]
// Runs one forced check against live (or mock) data and prints the dashboard.

var settings = MonitorSettings.default
var apiKey = ProcessInfo.processInfo.environment["TWELVE_DATA_API_KEY"]
var args = Array(CommandLine.arguments.dropFirst())
while !args.isEmpty {
    let arg = args.removeFirst()
    switch arg {
    case "--source":
        if let v = args.first, let s = DataSource(rawValue: v) { settings.dataSource = s; args.removeFirst() }
    case "--etf": settings.useETFProxies = true
    case "--all": settings.watchedIndexIDs = MarketIndex.all.map(\.id)
    case "--key": if !args.isEmpty { apiKey = args.removeFirst() }
    default: print("Unknown argument \(arg)")
    }
}
for kind in DetectorKind.allCases { settings.detectors[kind]?.isEnabled = true }

let dir = FileManager.default.temporaryDirectory.appendingPathComponent("fdk-check-\(UUID().uuidString)")
let key = apiKey
let runner = MonitorRunner(directory: dir) { s in ProviderFactory.make(s.dataSource, apiKey: key) }
let result = await runner.run(settings: settings, force: true)

let timeFormat = DateFormatter()
timeFormat.timeZone = MarketCalendar.nyse.timeZone
timeFormat.dateFormat = "yyyy-MM-dd HH:mm 'ET'"

print("Source: \(settings.dataSource.title) · Market: \(result.marketStatus.title) · Checked \(timeFormat.string(from: result.checkedAt))")
print("Alerts evaluated: \(result.alertsEvaluated)")
for status in result.statuses {
    print("")
    print("\(status.index.name) [\(status.symbol)]  \(AlertFormatter.price(status.price))  quote \(timeFormat.string(from: status.quoteTime))\(status.isStale ? "  (stale)" : "")")
    for e in status.evaluations {
        let mark = e.isBreached ? "BREACHED" : (e.isNearThreshold ? "near" : "ok")
        let ref = e.kind == .daily ? "prev close" : "high"
        print("  \(e.kind.shortLabel.padding(toLength: 11, withPad: " ", startingAt: 0)) \(AlertFormatter.signedPercent(e.changePercent).padding(toLength: 8, withPad: " ", startingAt: 0))  \(ref) \(AlertFormatter.price(e.referencePrice))  threshold \(AlertFormatter.percent(e.threshold))  \(mark)\(e.isPartialWindow ? " (partial history)" : "")")
    }
}
for (id, message) in result.errors.sorted(by: { $0.key < $1.key }) {
    print("ERROR \(id): \(message)")
}
if let n = AlertFormatter.notification(for: result.newAlerts) {
    print("\nWould notify:\n  \(n.title)\n  \(n.body)")
} else {
    print("\nNo notification.")
}
try? FileManager.default.removeItem(at: dir)
