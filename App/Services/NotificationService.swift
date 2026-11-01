import Foundation
import UserNotifications
import DetectorCore

final class NotificationService: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    static let shared = NotificationService()

    static let categoryID = "MARKET_DROP"
    static let snoozeActionID = "SNOOZE_TODAY"
    static let viewActionID = "VIEW"

    private let center = UNUserNotificationCenter.current()

    func configure() {
        center.delegate = self
        let snooze = UNNotificationAction(identifier: Self.snoozeActionID, title: "Snooze today", options: [])
        let view = UNNotificationAction(identifier: Self.viewActionID, title: "View", options: [.foreground])
        let category = UNNotificationCategory(identifier: Self.categoryID, actions: [view, snooze],
                                              intentIdentifiers: [], options: [])
        center.setNotificationCategories([category])
    }

    func requestAuthorization() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }

    /// Posts one notification for all alerts of a check (grouped when there are several).
    func post(_ alerts: [AlertEvent], timeSensitive: Bool, isTest: Bool = false) async {
        guard let text = AlertFormatter.notification(for: alerts) else { return }
        let content = UNMutableNotificationContent()
        content.title = isTest ? "[Test] " + text.title : text.title
        content.body = text.body
        content.sound = .default
        content.categoryIdentifier = Self.categoryID
        let indexIDs = Set(alerts.map(\.indexID))
        content.threadIdentifier = indexIDs.count == 1 ? alerts[0].indexID : "market"
        content.userInfo = ["indexIDs": Array(indexIDs)]
        if timeSensitive {
            content.interruptionLevel = .timeSensitive
        }
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        try? await center.add(request)
    }

    // MARK: UNUserNotificationCenterDelegate

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse) async {
        if response.actionIdentifier == Self.snoozeActionID {
            await AppModel.shared.snoozeToday()
        }
    }
}
