import Foundation

/// Result of one detector for one index. `dropPercent` is positive when the price is below the reference.
public struct DetectorEvaluation: Codable, Hashable, Identifiable, Sendable {
    public var id: String { "\(indexID)|\(kind.rawValue)" }
    public var indexID: String
    public var kind: DetectorKind
    public var dropPercent: Double
    public var threshold: Double
    /// Previous close (daily) or trailing-window high (drawdown detectors).
    public var referencePrice: Double
    public var price: Double
    public var isEnabled: Bool
    public var isBreached: Bool
    /// True when there was less history than the window needs (e.g. a new data source).
    public var isPartialWindow: Bool

    public init(indexID: String, kind: DetectorKind, dropPercent: Double, threshold: Double, referencePrice: Double,
                price: Double, isEnabled: Bool, isBreached: Bool, isPartialWindow: Bool) {
        self.indexID = indexID
        self.kind = kind
        self.dropPercent = dropPercent
        self.threshold = threshold
        self.referencePrice = referencePrice
        self.price = price
        self.isEnabled = isEnabled
        self.isBreached = isBreached
        self.isPartialWindow = isPartialWindow
    }

    /// Signed change versus the reference, e.g. -2.4.
    public var changePercent: Double { -dropPercent }

    /// Within one percentage point of the threshold but not breached.
    public var isNearThreshold: Bool { isEnabled && !isBreached && dropPercent >= threshold - 1.0 }
}

public enum DetectorEngine {
    /// Moves larger than this in a single session are treated as bad data.
    public static let maxPlausibleDailyMove = 25.0
    static let epsilon = 1e-9

    public static func isPlausible(_ snapshot: IndexSnapshot) -> Bool {
        abs(snapshot.dailyChangePercent) <= maxPlausibleDailyMove
    }

    /// Evaluates every detector kind (enabled or not, so the dashboard can show values for all of them).
    public static func evaluate(_ snapshot: IndexSnapshot, settings: MonitorSettings) -> [DetectorEvaluation] {
        DetectorKind.allCases.map { kind in
            let cfg = settings.config(for: kind)
            var reference = snapshot.previousClose
            var partial = false
            if let window = kind.windowTradingDays {
                let windowCloses = snapshot.closes.suffix(window)
                partial = windowCloses.count < window
                reference = max(windowCloses.max() ?? snapshot.price, snapshot.price)
            }
            let drop = reference > 0 ? (reference - snapshot.price) / reference * 100 : 0
            return DetectorEvaluation(
                indexID: snapshot.index.id,
                kind: kind,
                dropPercent: drop,
                threshold: cfg.threshold,
                referencePrice: reference,
                price: snapshot.price,
                isEnabled: cfg.isEnabled,
                isBreached: cfg.isEnabled && drop >= cfg.threshold - epsilon,
                isPartialWindow: partial
            )
        }
    }
}
