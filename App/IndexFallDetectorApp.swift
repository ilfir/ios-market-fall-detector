import SwiftUI

@main
struct IndexFallDetectorApp: App {
    @StateObject private var model = AppModel.shared

    init() {
        NotificationService.shared.configure()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
        }
        .backgroundRefresh()
    }
}

private extension Scene {
    /// Runs a monitoring check whenever iOS grants the app a background refresh slot.
    func backgroundRefresh() -> some Scene {
        #if os(iOS)
        return backgroundTask(.appRefresh(BackgroundScheduler.taskIdentifier)) {
            await AppModel.shared.handleBackgroundRefresh()
        }
        #else
        return self
        #endif
    }
}
