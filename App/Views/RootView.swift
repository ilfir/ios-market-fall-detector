import SwiftUI

struct RootView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TabView {
            DashboardView()
                .tabItem { Label("Market", systemImage: "chart.line.downtrend.xyaxis") }
            HistoryView()
                .tabItem { Label("Alerts", systemImage: "bell") }
                .badge(model.history.filter { Calendar.current.isDateInToday($0.timestamp) }.count)
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
        .onChange(of: scenePhase) { phase in
            switch phase {
            case .active: Task { await model.appBecameActive() }
            case .background: model.appEnteredBackground()
            default: break
            }
        }
        .sheet(isPresented: Binding(get: { !model.hasCompletedOnboarding },
                                    set: { if !$0 { model.hasCompletedOnboarding = true } })) {
            OnboardingView()
                .environmentObject(model)
                .interactiveDismissDisabled()
        }
    }
}

// MARK: - Shared helpers

enum ET {
    static func time(_ date: Date) -> String {
        let f = DateFormatter()
        f.timeZone = MarketCalendarZone.newYork
        f.dateFormat = Calendar.current.isDateInToday(date) ? "h:mm a 'ET'" : "EEE MMM d, h:mm a 'ET'"
        return f.string(from: date)
    }
}

enum MarketCalendarZone {
    static let newYork = TimeZone(identifier: "America/New_York")!
}

extension View {
    /// Decimal keypad on iPhone; no-op elsewhere.
    func decimalKeyboard() -> some View {
        #if os(iOS)
        return keyboardType(.decimalPad)
        #else
        return self
        #endif
    }
}
