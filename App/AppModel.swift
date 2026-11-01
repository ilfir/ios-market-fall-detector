import Foundation
import UserNotifications
import DetectorCore
import MarketData

@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    @Published var settings: MonitorSettings {
        didSet {
            guard settings != oldValue else { return }
            SettingsStore.save(settings)
            if settings.intervalMinutes != oldValue.intervalMinutes || settings.marketHoursOnly != oldValue.marketHoursOnly {
                scheduleBackgroundRefresh()
                startForegroundTimer()
            }
        }
    }
    @Published private(set) var lastResult: CheckResult?
    @Published private(set) var history: [AlertEvent] = []
    @Published private(set) var isChecking = false
    @Published private(set) var notificationStatus: UNAuthorizationStatus = .notDetermined
    @Published var hasCompletedOnboarding: Bool {
        didSet { UserDefaults.standard.set(hasCompletedOnboarding, forKey: Self.onboardingKey) }
    }

    let calendar = MarketCalendar.nyse
    private let runner: MonitorRunner
    private var foregroundTimer: Timer?
    private static let onboardingKey = "hasCompletedOnboarding"

    private init() {
        settings = SettingsStore.load()
        hasCompletedOnboarding = UserDefaults.standard.bool(forKey: Self.onboardingKey)
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("IndexFallDetector", isDirectory: true)
        runner = MonitorRunner(directory: directory) { settings in
            ProviderFactory.make(settings.dataSource, apiKey: KeychainService.read(.twelveDataAPIKey))
        }
        Task { await loadPersisted() }
    }

    private func loadPersisted() async {
        lastResult = await runner.lastResult()
        history = await runner.history()
    }

    // MARK: - Checks

    var nextCheckDate: Date {
        if settings.marketHoursOnly {
            return calendar.nextCheck(after: Date(), intervalMinutes: settings.intervalMinutes)
        }
        let base = lastResult?.checkedAt ?? Date()
        return max(Date(), base.addingTimeInterval(Double(settings.intervalMinutes) * 60))
    }

    /// - Parameter force: fetch even when the market is closed (manual refresh, app opened).
    @discardableResult
    func runCheck(force: Bool) async -> CheckResult? {
        guard !isChecking else { return lastResult }
        isChecking = true
        defer { isChecking = false }

        let result = await runner.run(settings: settings, now: Date(), force: force)
        lastResult = result
        if !result.newAlerts.isEmpty {
            history = await runner.history()
            if !settings.isSnoozed(at: Date()) {
                await NotificationService.shared.post(result.newAlerts, timeSensitive: settings.timeSensitiveAlerts)
            }
        }
        return result
    }

    func appBecameActive() async {
        await refreshNotificationStatus()
        scheduleBackgroundRefresh()
        startForegroundTimer()
        let isOld = lastResult.map { Date().timeIntervalSince($0.checkedAt) > 60 } ?? true
        if isOld || lastResult?.statuses.isEmpty == true {
            await runCheck(force: true)
        }
    }

    func appEnteredBackground() {
        foregroundTimer?.invalidate()
        foregroundTimer = nil
        scheduleBackgroundRefresh()
    }

    func handleBackgroundRefresh() async {
        scheduleBackgroundRefresh()
        await runCheck(force: false)
    }

    func scheduleBackgroundRefresh() {
        #if os(iOS)
        BackgroundScheduler.schedule(earliest: nextCheckDate)
        #endif
    }

    /// While the app is open, check on the same interval without waiting for iOS.
    private func startForegroundTimer() {
        foregroundTimer?.invalidate()
        let interval = Double(settings.intervalMinutes) * 60
        foregroundTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in
            Task { @MainActor in await AppModel.shared.runCheck(force: false) }
        }
    }

    // MARK: - Notifications

    func refreshNotificationStatus() async {
        notificationStatus = await NotificationService.shared.authorizationStatus()
    }

    func requestNotifications() async {
        _ = await NotificationService.shared.requestAuthorization()
        await refreshNotificationStatus()
    }

    func snoozeToday() {
        settings.snoozedUntil = calendar.startOfNextDay(after: Date())
    }

    func cancelSnooze() {
        settings.snoozedUntil = nil
    }

    func sendTestNotification() async {
        let sample = AlertEvent(timestamp: Date(), indexID: MarketIndex.sp500.id, indexName: MarketIndex.sp500.name,
                                kind: .daily, dropPercent: settings.config(for: .daily).threshold + 0.4,
                                threshold: settings.config(for: .daily).threshold, referencePrice: 5_750,
                                price: 5_750 * (1 - (settings.config(for: .daily).threshold + 0.4) / 100),
                                isEscalation: false)
        await NotificationService.shared.post([sample], timeSensitive: settings.timeSensitiveAlerts, isTest: true)
    }

    // MARK: - Maintenance

    func resetAlertState() async {
        await runner.resetAlertStates()
    }

    func clearHistory() async {
        await runner.clearHistory()
        history = []
    }
}

enum SettingsStore {
    private static let key = "monitorSettings.v1"

    static func load() -> MonitorSettings {
        guard let data = UserDefaults.standard.data(forKey: key),
              let settings = try? JSONDecoder().decode(MonitorSettings.self, from: data) else { return .default }
        return settings.normalized()
    }

    static func save(_ settings: MonitorSettings) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
