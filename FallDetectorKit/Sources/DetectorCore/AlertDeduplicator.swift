import Foundation

/// Per index + detector memory used to avoid repeating the same alert.
public struct AlertState: Codable, Equatable, Sendable {
    public var isArmed: Bool
    public var lastAlertDay: String?
    public var lastAlertLevel: Double?
    /// Threshold in effect when this state was written; a change resets the state.
    public var threshold: Double?

    public init(isArmed: Bool = true, lastAlertDay: String? = nil, lastAlertLevel: Double? = nil, threshold: Double? = nil) {
        self.isArmed = isArmed
        self.lastAlertDay = lastAlertDay
        self.lastAlertLevel = lastAlertLevel
        self.threshold = threshold
    }
}

public struct AlertEvent: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var timestamp: Date
    public var indexID: String
    public var indexName: String
    public var kind: DetectorKind
    public var dropPercent: Double
    public var threshold: Double
    public var referencePrice: Double
    public var price: Double
    /// True when this re-alerts a detector that already fired and has since dropped further.
    public var isEscalation: Bool

    public init(id: UUID = UUID(), timestamp: Date, indexID: String, indexName: String, kind: DetectorKind,
                dropPercent: Double, threshold: Double, referencePrice: Double, price: Double, isEscalation: Bool) {
        self.id = id
        self.timestamp = timestamp
        self.indexID = indexID
        self.indexName = indexName
        self.kind = kind
        self.dropPercent = dropPercent
        self.threshold = threshold
        self.referencePrice = referencePrice
        self.price = price
        self.isEscalation = isEscalation
    }
}

/// Turns evaluations into alerts while suppressing repeats:
/// - a detector fires once when it first crosses its threshold,
/// - fires again only if the drop deepens by `escalationStep` points,
/// - re-arms after recovering to `threshold - hysteresis` (the daily detector also re-arms each new session),
/// - changing a threshold or disabling a detector resets its state.
public struct AlertDeduplicator: Sendable {
    public var escalationStep: Double
    public var hysteresis: Double

    public init(escalationStep: Double, hysteresis: Double) {
        self.escalationStep = escalationStep
        self.hysteresis = hysteresis
    }

    public init(settings: MonitorSettings) {
        self.init(escalationStep: settings.escalationStep, hysteresis: settings.hysteresis)
    }

    public static func key(indexID: String, kind: DetectorKind) -> String { "\(indexID)|\(kind.rawValue)" }

    public func process(_ evaluations: [DetectorEvaluation], index: MarketIndex, sessionDay: String,
                        states: inout [String: AlertState], now: Date) -> [AlertEvent] {
        var events: [AlertEvent] = []
        for e in evaluations {
            let key = Self.key(indexID: e.indexID, kind: e.kind)
            guard e.isEnabled else {
                states[key] = nil
                continue
            }
            var st = states[key] ?? AlertState(threshold: e.threshold)
            if st.threshold != e.threshold {
                st = AlertState(threshold: e.threshold)
            }
            if e.kind == .daily, st.lastAlertDay != sessionDay {
                st.isArmed = true
                st.lastAlertLevel = nil
            }

            if e.isBreached {
                var fire = false
                var escalation = false
                if st.isArmed {
                    fire = true
                } else if let level = st.lastAlertLevel, e.dropPercent >= level + escalationStep - DetectorEngine.epsilon {
                    fire = true
                    escalation = true
                }
                if fire {
                    events.append(AlertEvent(timestamp: now, indexID: e.indexID, indexName: index.name, kind: e.kind,
                                             dropPercent: e.dropPercent, threshold: e.threshold,
                                             referencePrice: e.referencePrice, price: e.price, isEscalation: escalation))
                    st.isArmed = false
                    st.lastAlertLevel = e.dropPercent
                    st.lastAlertDay = sessionDay
                }
            } else if e.dropPercent < e.threshold - hysteresis {
                st.isArmed = true
                st.lastAlertLevel = nil
            }
            states[key] = st
        }
        return events
    }
}
