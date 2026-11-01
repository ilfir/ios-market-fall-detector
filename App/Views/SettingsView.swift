import SwiftUI
import DetectorCore

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var apiKey = ""
    @State private var apiKeySaved = false
    @State private var confirmReset = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(DetectorKind.allCases) { kind in
                        DetectorRow(kind: kind, config: detectorBinding(kind))
                    }
                } header: {
                    Text("Detectors")
                } footer: {
                    if !model.settings.detectors.values.contains(where: \.isEnabled) {
                        Text("All detectors are off, so no alerts will be sent.").foregroundColor(.orange)
                    }
                }

                Section {
                    Picker("Check every", selection: $model.settings.intervalMinutes) {
                        ForEach(MonitorSettings.allowedIntervals, id: \.self) { Text("\($0) min").tag($0) }
                    }
                    .pickerStyle(.segmented)
                    Toggle("Market hours only", isOn: $model.settings.marketHoursOnly)
                } header: {
                    Text("Checking")
                } footer: {
                    Text("Checks run 9:30 am – 4:05 pm ET on trading days. While the app is closed, iOS decides exactly when background checks run, so some may be late or skipped.")
                }

                Section {
                    ForEach(MarketIndex.all) { index in
                        Toggle(isOn: indexBinding(index)) {
                            VStack(alignment: .leading) {
                                Text(index.name)
                                Text(index.symbol(for: model.settings.dataSource, useETF: model.settings.useETFProxies))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                } header: {
                    Text("Indices")
                } footer: {
                    if model.settings.watchedIndices.isEmpty {
                        Text("No index selected, so monitoring is paused.").foregroundColor(.orange)
                    }
                }

                Section {
                    Stepper(value: $model.settings.escalationStep, in: 0.5...5, step: 0.5) {
                        HStack {
                            Text("Re-alert if worse by")
                            Spacer()
                            Text(String(format: "%.1f pp", model.settings.escalationStep)).foregroundColor(.secondary)
                        }
                    }
                    Toggle("Time-sensitive alerts", isOn: $model.settings.timeSensitiveAlerts)
                    if model.settings.isSnoozed(at: Date()) {
                        Button("Resume alerts (snoozed today)") { model.cancelSnooze() }
                    } else {
                        Button("Snooze for the rest of today") { model.snoozeToday() }
                    }
                    Button("Send test notification") {
                        Task {
                            if model.notificationStatus == .notDetermined { await model.requestNotifications() }
                            await model.sendTestNotification()
                        }
                    }
                } header: {
                    Text("Alerts")
                } footer: {
                    Text("Each detector alerts once when it crosses its threshold, then again only if the drop deepens by the step above. Time-sensitive alerts can break through Focus modes.")
                }

                Section {
                    Picker("Data source", selection: $model.settings.dataSource) {
                        ForEach(DataSource.allCases) { Text($0.title).tag($0) }
                    }
                    if model.settings.dataSource.requiresAPIKey {
                        HStack {
                            SecureField("API key", text: $apiKey)
                                .textContentType(.password)
                                .autocorrectionDisabled()
                            Button(apiKeySaved ? "Saved" : "Save") {
                                apiKeySaved = KeychainService.save(apiKey.trimmingCharacters(in: .whitespaces), for: .twelveDataAPIKey)
                            }
                            .disabled(apiKey.isEmpty)
                        }
                    }
                    Toggle("Use ETF proxies (SPY, DIA, QQQ…)", isOn: $model.settings.useETFProxies)
                } header: {
                    Text("Data")
                } footer: {
                    Text(dataFooter)
                }

                Section("Maintenance") {
                    Button("Reset alert memory", role: .destructive) { confirmReset = true }
                }
            }
            .navigationTitle("Settings")
            .onAppear {
                apiKey = KeychainService.read(.twelveDataAPIKey) ?? ""
                apiKeySaved = !apiKey.isEmpty
            }
            .onChange(of: apiKey) { _ in apiKeySaved = false }
            .confirmationDialog("Reset alert memory?", isPresented: $confirmReset, titleVisibility: .visible) {
                Button("Reset", role: .destructive) { Task { await model.resetAlertState() } }
            } message: {
                Text("Detectors that are already past their threshold will alert again on the next check.")
            }
        }
    }

    private var dataFooter: String {
        switch model.settings.dataSource {
        case .yahoo: return "Yahoo Finance is free and needs no key, but it is an unofficial API meant for personal use and may change without notice."
        case .twelveData: return "The free Twelve Data plan covers ETFs; turn on ETF proxies unless your plan includes index data."
        case .mock: return "Demo data is generated on the device and always shows a drop, which is useful for trying out alerts."
        }
    }

    private func detectorBinding(_ kind: DetectorKind) -> Binding<DetectorConfig> {
        Binding(
            get: { model.settings.config(for: kind) },
            set: { newValue in
                var config = newValue
                config.threshold = MonitorSettings.clampThreshold(config.threshold)
                model.settings.detectors[kind] = config
            }
        )
    }

    private func indexBinding(_ index: MarketIndex) -> Binding<Bool> {
        Binding(
            get: { model.settings.watchedIndexIDs.contains(index.id) },
            set: { on in
                var ids = model.settings.watchedIndexIDs.filter { $0 != index.id }
                if on { ids.append(index.id) }
                model.settings.watchedIndexIDs = MarketIndex.all.map(\.id).filter(ids.contains)
            }
        )
    }
}

private struct DetectorRow: View {
    let kind: DetectorKind
    @Binding var config: DetectorConfig

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: $config.isEnabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(kind.title)
                    Text(kind.explanation).font(.caption).foregroundColor(.secondary)
                }
            }
            HStack(spacing: 6) {
                Text(kind == .daily ? "Alert when down ≥" : "Below \(kind.windowName) high by ≥")
                    .font(.subheadline)
                Spacer()
                TextField("%", value: $config.threshold, format: .number.precision(.fractionLength(1)))
                    .multilineTextAlignment(.trailing)
                    .frame(width: 52)
                    .decimalKeyboard()
                Text("%")
                Stepper("Threshold", value: $config.threshold, in: MonitorSettings.thresholdRange, step: 0.5)
                    .labelsHidden()
            }
            .disabled(!config.isEnabled)
            .opacity(config.isEnabled ? 1 : 0.4)
        }
        .padding(.vertical, 2)
    }
}
