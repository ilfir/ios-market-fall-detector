import Foundation

public enum AlertFormatter {
    private static let minus = "\u{2212}"

    /// "2.4%" (always positive).
    public static func percent(_ value: Double, digits: Int = 1) -> String {
        String(format: "%.\(digits)f%%", abs(value))
    }

    /// "−2.40%" / "+0.35%".
    public static func signedPercent(_ value: Double, digits: Int = 2) -> String {
        let sign = value < 0 ? minus : "+"
        return sign + String(format: "%.\(digits)f%%", abs(value))
    }

    public static func price(_ value: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.minimumFractionDigits = 2
        f.maximumFractionDigits = 2
        f.locale = Locale(identifier: "en_US")
        return f.string(from: NSNumber(value: value)) ?? String(format: "%.2f", value)
    }

    /// "S&P 500 down 2.4% today" / "Nasdaq Composite 10.3% below 6-month high".
    public static func headline(_ e: AlertEvent) -> String {
        switch e.kind {
        case .daily:
            return "\(e.indexName) down \(percent(e.dropPercent)) today"
        default:
            return "\(e.indexName) \(percent(e.dropPercent)) below \(e.kind.windowName) high"
        }
    }

    public static func detail(_ e: AlertEvent) -> String {
        switch e.kind {
        case .daily:
            let points = e.price - e.referencePrice
            let sign = points < 0 ? minus : "+"
            return "\(price(e.price)) (\(sign)\(price(abs(points)))) · Threshold: \(percent(e.threshold))"
        default:
            return "\(price(e.price)) vs high \(price(e.referencePrice)) · Threshold: \(percent(e.threshold))"
        }
    }

    /// Compact form for grouped notifications: "−2.4% today" / "−7.8% vs 3M high".
    public static func compact(_ e: AlertEvent) -> String {
        let value = minus + percent(e.dropPercent)
        return e.kind == .daily ? "\(value) today" : "\(value) \(e.kind.shortLabel)"
    }

    public static func notification(for events: [AlertEvent]) -> (title: String, body: String)? {
        guard let first = events.first else { return nil }
        if events.count == 1 {
            let title = "📉 " + headline(first) + (first.isEscalation ? " (worse)" : "")
            return (title, detail(first))
        }
        var order: [String] = []
        var byIndex: [String: [AlertEvent]] = [:]
        for e in events {
            if byIndex[e.indexID] == nil { order.append(e.indexID) }
            byIndex[e.indexID, default: []].append(e)
        }
        let body = order.compactMap { id -> String? in
            guard let group = byIndex[id], let name = group.first?.indexName else { return nil }
            return "\(name): " + group.map(compact).joined(separator: ", ")
        }.joined(separator: " · ")
        return ("📉 Market drop alert (\(events.count) triggers)", body)
    }
}
