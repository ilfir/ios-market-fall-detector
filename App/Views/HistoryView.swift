import SwiftUI
import DetectorCore

struct HistoryView: View {
    @EnvironmentObject private var model: AppModel
    @State private var confirmClear = false

    var body: some View {
        NavigationStack {
            Group {
                if model.history.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "bell.badge").font(.largeTitle).foregroundColor(.secondary)
                        Text("No alerts yet").font(.headline)
                        Text("Alerts from the last 90 days appear here.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(groupedByDay, id: \.day) { group in
                            Section(group.day) {
                                ForEach(group.events) { AlertRow(event: $0) }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Alert History")
            .toolbar {
                if !model.history.isEmpty {
                    ToolbarItem(placement: .primaryAction) {
                        Button("Clear") { confirmClear = true }
                    }
                }
            }
            .confirmationDialog("Clear alert history?", isPresented: $confirmClear, titleVisibility: .visible) {
                Button("Clear history", role: .destructive) { Task { await model.clearHistory() } }
            }
        }
    }

    private var groupedByDay: [(day: String, events: [AlertEvent])] {
        let f = DateFormatter()
        f.timeZone = MarketCalendarZone.newYork
        f.dateFormat = "EEEE, MMM d"
        var order: [String] = []
        var groups: [String: [AlertEvent]] = [:]
        for event in model.history {
            let day = f.string(from: event.timestamp)
            if groups[day] == nil { order.append(day) }
            groups[day, default: []].append(event)
        }
        return order.map { ($0, groups[$0] ?? []) }
    }
}

private struct AlertRow: View {
    let event: AlertEvent

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(AlertFormatter.headline(event)).font(.subheadline.bold())
                if event.isEscalation {
                    Text("worse").font(.caption2.bold()).foregroundColor(.red)
                }
            }
            Text(AlertFormatter.detail(event)).font(.caption).foregroundColor(.secondary)
            Text(ET.time(event.timestamp)).font(.caption2).foregroundColor(.secondary)
        }
        .padding(.vertical, 2)
    }
}
