import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "chart.line.downtrend.xyaxis")
                .font(.system(size: 64))
                .foregroundColor(.red)
            Text("Index Fall Detector")
                .font(.largeTitle.bold())
            VStack(alignment: .leading, spacing: 14) {
                point("bell.badge", "Get notified when the S&P 500, Dow or Nasdaq drops past the thresholds you set.")
                point("slider.horizontal.3", "Turn each detector on or off: today's fall, and the drop from the 3-month, 6-month and 1-year high.")
                point("clock", "The market is checked every 15 or 30 minutes during trading hours.")
            }
            .padding(.horizontal)
            Spacer()
            Button {
                Task {
                    await model.requestNotifications()
                    model.hasCompletedOnboarding = true
                }
            } label: {
                Text("Enable Notifications").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            Button("Not now") { model.hasCompletedOnboarding = true }
                .padding(.bottom)
        }
        .padding()
    }

    private func point(_ icon: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon).frame(width: 28).foregroundColor(.accentColor)
            Text(text)
        }
    }
}
