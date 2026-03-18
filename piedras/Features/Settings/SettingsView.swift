import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SettingsStore.self) private var settingsStore
    @Environment(MeetingStore.self) private var meetingStore

    var body: some View {
        ZStack {
            AppGlassBackdrop()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    header

                    AppGlassCard(cornerRadius: 28, style: .regular, padding: 16, shadowOpacity: 0.06) {
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

                    AppGlassCard(cornerRadius: 28, style: .regular, padding: 16, shadowOpacity: 0.06) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(AppEnvironment.cloudName)
                                .font(.headline)
                                .foregroundStyle(AppTheme.ink)

                            Text(settingsStore.backendDisplayURLString)
                                .font(.footnote)
                                .foregroundStyle(AppTheme.subtleInk)
                                .textSelection(.enabled)

                            AppGlassCapsuleButton(
                                prominent: !settingsStore.isCheckingHealth,
                                minHeight: 42,
                                action: {
                                    Task {
                                        await meetingStore.checkBackendHealth(force: true)
                                    }
                                }
                            ) {
                                Text(settingsStore.isCheckingHealth ? "Checking..." : "Refresh Status")
                                    .font(.subheadline.weight(.semibold))
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

                    AppGlassCard(cornerRadius: 28, style: .regular, padding: 16, shadowOpacity: 0.06) {
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
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 32)
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
                    .font(.system(size: 30, weight: .regular, design: .serif))
                    .foregroundStyle(AppTheme.ink)

                Text("Service & status")
                    .font(.footnote)
                    .foregroundStyle(AppTheme.subtleInk)
            }

            Spacer()

            AppGlassCircleButton(systemName: "xmark", accessibilityLabel: "关闭", size: 40) {
                dismiss()
            }
        }
    }

    private func settingsRow(systemName: String, title: String, value: String) -> some View {
        HStack(spacing: 10) {
            GlassIconBadge(systemName: systemName, size: 28, symbolSize: 11, shape: .rounded(12))

            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.ink)

            Spacer()

            Text(value)
                .font(.footnote.weight(.medium))
                .foregroundStyle(AppTheme.subtleInk)
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 11)
    }

    private func statusRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.ink)

            Spacer()

            Text(value)
                .font(.footnote)
                .foregroundStyle(AppTheme.subtleInk)
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 11)
    }

    private var cloudHelpText: String {
        switch settingsStore.backendCapabilityStatus {
        case .checking:
            return "Checking current endpoint and capabilities."
        case .standby:
            return "Connects to \(AppEnvironment.cloudName) by default."
        case .ready:
            return "Current endpoint: \(settingsStore.backendHostLabel)"
        case .offline, .unavailable:
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
        switch settingsStore.backendCapabilityStatus {
        case .checking:
            return "Checking..."
        case .standby:
            return "Standby"
        case .ready:
            return settingsStore.backendStatusMessage
        case .offline, .unavailable:
            return settingsStore.backendStatusMessage
        }
    }

    private var asrStateLabel: String {
        switch settingsStore.asrCapabilityStatus {
        case .checking:
            return "Checking..."
        case .standby:
            return "Standby"
        case .ready, .unavailable, .offline:
            return settingsStore.asrStatusMessage
        }
    }

    private var llmStateLabel: String {
        switch settingsStore.llmCapabilityStatus {
        case .checking:
            return "Checking..."
        case .standby:
            return "Standby"
        case .offline, .unavailable:
            return settingsStore.llmStatusMessage
        case .ready:
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
