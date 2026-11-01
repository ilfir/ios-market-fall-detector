#if os(iOS)
import BackgroundTasks
import Foundation

/// Asks iOS for the next background refresh. iOS decides the actual run time: it can be later
/// than requested, or skipped when the app is rarely used or Low Power Mode is on.
enum BackgroundScheduler {
    /// Must match BGTaskSchedulerPermittedIdentifiers in Info.plist.
    static let taskIdentifier = "com.example.IndexFallDetector.refresh"

    static func schedule(earliest: Date) {
        let request = BGAppRefreshTaskRequest(identifier: taskIdentifier)
        request.earliestBeginDate = earliest
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: taskIdentifier)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            // Fails in the Simulator and when Background App Refresh is turned off; foreground checks still work.
            print("BGTaskScheduler submit failed: \(error)")
        }
    }
}
#endif
