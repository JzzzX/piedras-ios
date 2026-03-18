import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SettingsStore.self) private var settingsStore
    @Environment(MeetingStore.self) private var meetingStore

    var body: some View {
        ZStack {
            AppGlassBackdrop()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    header

                    AppGlassCard(cornerRadius: 34, style: .regular, padding: 20, shadowOpacity: 0.08) {
                        VStack(spacing: 0) {
                            settingsRow(systemName: "network", title: "Service", value: settingsStore.serviceModeLabel)
                            AppGlassDivider(inset: 42)
                            settingsRow(systemName: "mic.fill", title: "Recording", value: "16 kHz")
                            AppGlassDivider(inset: 42)
                            settingsRow(systemName: "internaldrive", title: "Storage", value: "On Device")
                            AppGlassDivider(inset: 42)
                            settingsRow(systemName: "app.badge", title: "Version", value: AppEnvironment.versionDescription)
                        }
                    }

                    AppGlassCard(cornerRadius: 34, style: .regular, padding: 20, shadowOpacity: 0.08) {
                        VStack(alignment: .leading, spacing: 14) {
                            Text(AppEnvironment.cloudName)
                                .font(.headline)
                                .foregroundStyle(AppTheme.ink)

                            Text(settingsStore.backendDisplayURLString)
                                .font(.footnote)
                                .foregroundStyle(AppTheme.subtleInk)
                                .textSelection(.enabled)

                            AppGlassCapsuleButton(
                                prominent: !settingsStore.isCheckingHealth,
                                minHeight: 48,
                                action: {
                                    Task {
                                        await meetingStore.checkBackendHealth(force: true)
                                    }
                                }
                            ) {
                                Text(settingsStore.isCheckingHealth ? "Checking..." : "Refresh Status")
                                    .font(.headline)
                                    .foregroundStyle(settingsStore.isCheckingHealth ? AppTheme.subtleInk : .white)
                            }
                            .disabled(settingsStore.isCheckingHealth)

                            Text(cloudHelpText)
                                .font(.footnote)
                                .foregroundStyle(AppTheme.subtleInk)

                            #if DEBUG
                            if settingsStore.isUsingDebugBackendOverride {
                                Button("Use Cloud Default") {
                                    settingsStore.clearDebugBackendOverride()
                                }
                                .buttonStyle(.plain)
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(AppTheme.ink)
                            }
                            #endif
                        }
                    }

                    AppGlassCard(cornerRadius: 34, style: .regular, padding: 20, shadowOpacity: 0.08) {
                        VStack(spacing: 0) {
                            statusRow(title: "Backend", value: backendStateLabel)
                            AppGlassDivider(inset: 0)
                            statusRow(title: "ASR", value: asrStateLabel)
                            AppGlassDivider(inset: 0)
                            statusRow(title: "AI", value: llmStateLabel)
                            AppGlassDivider(inset: 0)
                            statusRow(title: "Sync", value: syncValue)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 40)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .task {
            await meetingStore.checkBackendHealth(force: false)
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Settings")
                    .font(.system(size: 36, weight: .regular, design: .serif))
                    .foregroundStyle(AppTheme.ink)

                Text("Service & status")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.subtleInk)
            }

            Spacer()

            AppGlassCircleButton(systemName: "xmark", accessibilityLabel: "关闭") {
                dismiss()
            }
        }
    }

    private func settingsRow(systemName: String, title: String, value: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemName)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(AppTheme.ink)
                .frame(width: 30, height: 30)
                .background {
                    AppGlassSurface(cornerRadius: 15, style: .clear, shadowOpacity: 0.03)
                }

            Text(title)
                .font(.headline)
                .foregroundStyle(AppTheme.ink)

            Spacer()

            Text(value)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(AppTheme.subtleInk)
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 14)
    }

    private func statusRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .font(.headline)
                .foregroundStyle(AppTheme.ink)

            Spacer()

            Text(value)
                .font(.subheadline)
                .foregroundStyle(AppTheme.subtleInk)
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 14)
    }

    private var cloudHelpText: String {
        switch settingsStore.backendConnectionState {
        case .configuredUnchecked:
            return "Connects to \(AppEnvironment.cloudName) by default."
        case .reachable:
            return "Current endpoint: \(settingsStore.backendHostLabel)"
        case .unreachable:
            return "\(AppEnvironment.cloudName) is offline or unreachable."
        }
    }

    private var syncValue: String {
        let message = settingsStore.syncStatusMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        return message.isEmpty ? "Idle" : message
    }

    private var transcriptValue: String {
        switch settingsStore.backendConnectionState {
        case .configuredUnchecked:
            return "Standby"
        case .reachable:
            return settingsStore.asrReady ? "Ready" : "Unavailable"
        case .unreachable:
            return "Offline"
        }
    }

    private var aiValue: String {
        switch settingsStore.backendConnectionState {
        case .configuredUnchecked:
            return "Standby"
        case .reachable:
            return settingsStore.llmReady ? "Ready" : "Unavailable"
        case .unreachable:
            return "Offline"
        }
    }

    private var backendStateLabel: String {
        switch settingsStore.backendConnectionState {
        case .configuredUnchecked:
            return "Standby"
        case .reachable:
            return settingsStore.backendStatusMessage
        case .unreachable:
            return "Offline"
        }
    }

    private var asrStateLabel: String {
        switch settingsStore.backendConnectionState {
        case .configuredUnchecked:
            return "Standby"
        case .reachable, .unreachable:
            return settingsStore.asrStatusMessage
        }
    }

    private var llmStateLabel: String {
        switch settingsStore.backendConnectionState {
        case .configuredUnchecked:
            return "Standby"
        case .unreachable:
            return "Offline"
        case .reachable:
            guard settingsStore.llmReady else {
                return settingsStore.llmStatusMessage
            }

            let provider = settingsStore.llmProvider.capitalized
            let preset = settingsStore.llmPreset.flatMap { $0.isEmpty ? nil : $0 }
            let model = settingsStore.llmModel.flatMap { $0.isEmpty ? nil : $0 }
            return [provider, preset, model].compactMap { $0 }.joined(separator: " · ")
        }
    }
}
