import SwiftUI
import Charts
import DetectorCore
import MarketData

struct DashboardView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        NavigationStack {
            List {
                Section {
                    StatusHeader()
                }
                banners
                if let result = model.lastResult, !result.statuses.isEmpty {
                    ForEach(result.statuses) { status in
                        Section {
                            IndexCard(status: status)
                        }
                    }
                } else if model.isChecking {
                    Section { HStack { Spacer(); ProgressView("Loading market data…"); Spacer() } }
                } else {
                    Section { Text("No data yet. Pull down to check the market.").foregroundColor(.secondary) }
                }
                if let errors = model.lastResult?.errors, !errors.isEmpty {
                    Section("Problems") {
                        ForEach(errors.sorted(by: { $0.key < $1.key }), id: \.key) { id, message in
                            Label("\(MarketIndex.with(id: id)?.name ?? id): \(message)", systemImage: "exclamationmark.triangle")
                                .font(.footnote)
                                .foregroundColor(.orange)
                        }
                    }
                }
                Section {
                    Text("Informational alerts only, not investment advice. Data may be delayed.")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .refreshable { await model.runCheck(force: true) }
            .navigationTitle("Market Watch")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        Task { await model.runCheck(force: true) }
                    } label: {
                        if model.isChecking { ProgressView() } else { Image(systemName: "arrow.clockwise") }
                    }
                    .disabled(model.isChecking)
                    .accessibilityLabel("Check now")
                }
            }
        }
    }

    @ViewBuilder private var banners: some View {
        if model.notificationStatus == .denied {
            Section {
                Label("Notifications are off. Turn them on in iOS Settings to receive drop alerts.", systemImage: "bell.slash")
                    .foregroundColor(.red)
                    .font(.subheadline)
            }
        }
        if model.settings.isSnoozed(at: Date()) {
            Section {
                HStack {
                    Label("Alerts snoozed for today", systemImage: "moon.zzz")
                    Spacer()
                    Button("Resume") { model.cancelSnooze() }
                }
                .font(.subheadline)
            }
        }
        if !model.settings.isMonitoringActive {
            Section {
                Label("Monitoring is paused: turn on at least one detector and one index in Settings.", systemImage: "pause.circle")
                    .foregroundColor(.orange)
                    .font(.subheadline)
            }
        }
    }
}

private struct StatusHeader: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        let status = model.calendar.status(at: Date())
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(status.title)
                    .font(.caption.bold())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(status == .open ? Color.green.opacity(0.2) : Color.secondary.opacity(0.15))
                    .clipShape(Capsule())
                Text("Every \(model.settings.intervalMinutes) min")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
            }
            if let checked = model.lastResult?.checkedAt {
                Text("Last checked \(ET.time(checked))")
                    .font(.subheadline)
            }
            Text("Next check \(ET.time(model.nextCheckDate))")
                .font(.footnote)
                .foregroundColor(.secondary)
        }
    }
}

struct IndexCard: View {
    let status: IndexStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(status.index.name).font(.headline)
                    Text(status.isStale ? "\(status.symbol) · stale data" : status.symbol)
                        .font(.caption)
                        .foregroundColor(status.isStale ? .orange : .secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(AlertFormatter.price(status.price))
                        .font(.title3.monospacedDigit().bold())
                    Text(AlertFormatter.signedPercent(status.dailyChangePercent))
                        .font(.subheadline.monospacedDigit())
                        .foregroundColor(status.dailyChangePercent < 0 ? .red : .green)
                }
            }
            Sparkline(values: status.recentCloses)
                .frame(height: 44)
            VStack(spacing: 6) {
                ForEach(status.evaluations) { evaluation in
                    DetectorStatusRow(evaluation: evaluation)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

enum DetectorLight {
    case off, ok, near, breached

    init(_ e: DetectorEvaluation) {
        if !e.isEnabled { self = .off }
        else if e.isBreached { self = .breached }
        else if e.isNearThreshold { self = .near }
        else { self = .ok }
    }

    var color: Color {
        switch self {
        case .off: return .gray.opacity(0.4)
        case .ok: return .green
        case .near: return .yellow
        case .breached: return .red
        }
    }

    var label: String {
        switch self {
        case .off: return "off"
        case .ok: return "OK"
        case .near: return "near threshold"
        case .breached: return "threshold reached"
        }
    }
}

private struct DetectorStatusRow: View {
    let evaluation: DetectorEvaluation

    var body: some View {
        let light = DetectorLight(evaluation)
        HStack {
            Circle().fill(light.color).frame(width: 9, height: 9)
            Text(evaluation.kind.shortLabel)
                .font(.subheadline)
            Spacer()
            Text(AlertFormatter.signedPercent(evaluation.changePercent))
                .font(.subheadline.monospacedDigit())
                .foregroundColor(evaluation.isEnabled ? .primary : .secondary)
            Text(evaluation.isEnabled ? "≥ \(AlertFormatter.percent(evaluation.threshold))" : "Off")
                .font(.caption.monospacedDigit())
                .foregroundColor(.secondary)
                .frame(width: 58, alignment: .trailing)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(evaluation.kind.title): \(AlertFormatter.signedPercent(evaluation.changePercent)), \(light.label)")
    }
}

private struct Sparkline: View {
    let values: [Double]

    var body: some View {
        let low = values.min() ?? 0
        let high = values.max() ?? 1
        let pad = max((high - low) * 0.05, 0.01)
        let falling = (values.last ?? 0) < (values.first ?? 0)
        Chart(Array(values.enumerated()), id: \.offset) { point in
            LineMark(x: .value("Day", point.offset), y: .value("Close", point.element))
                .interpolationMethod(.monotone)
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartYScale(domain: (low - pad)...(high + pad))
        .foregroundStyle(falling ? Color.red : Color.green)
        .accessibilityHidden(true)
    }
}
