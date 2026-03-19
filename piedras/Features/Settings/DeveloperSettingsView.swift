import SwiftUI

struct DeveloperSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SettingsStore.self) private var settingsStore
    @Environment(MeetingStore.self) private var meetingStore

    var body: some View {
        ZStack {
            AppGlassBackdrop()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    header

                    // General window
                    VStack(spacing: 0) {
                        RetroTitleBar(label: AppStrings.current.general)

                        VStack(spacing: 0) {
                            settingsRow(systemName: "network", title: AppStrings.current.service, value: settingsStore.serviceModeLabel)
                            RetroDivider(inset: 42)
                            settingsRow(systemName: "mic.fill", title: AppStrings.current.recordingQuality, value: "16 kHz")
                            RetroDivider(inset: 42)
                            settingsRow(systemName: "internaldrive", title: AppStrings.current.storage, value: AppStrings.current.onDevice)
                            RetroDivider(inset: 42)
                            settingsRow(systemName: "app.badge", title: AppStrings.current.version, value: AppEnvironment.versionDescription)
                        }
                        .padding(16)
                    }
                    .background(AppTheme.surface)
                    .overlay(
                        Rectangle()
                            .stroke(AppTheme.border, lineWidth: AppTheme.retroBorderWidth)
                    )
                    .retroHardShadow()

                    // Cloud window
                    VStack(spacing: 0) {
                        RetroTitleBar(label: AppStrings.current.cloud)

                        VStack(alignment: .leading, spacing: 12) {
                            Text(AppEnvironment.cloudName)
                                .font(.system(size: 17, weight: .bold, design: .monospaced))
                                .foregroundStyle(AppTheme.ink)

                            Text(settingsStore.backendDisplayURLString)
                                .font(.system(size: 13, weight: .regular, design: .monospaced))
                                .foregroundStyle(AppTheme.subtleInk)
                                .textSelection(.enabled)

                            Button {
                                Task {
                                    await meetingStore.checkBackendHealth(force: true)
                                }
                            } label: {
                                Text(settingsStore.isCheckingHealth ? AppStrings.current.checking : AppStrings.current.refreshStatus)
                                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                                    .foregroundStyle(settingsStore.isCheckingHealth ? AppTheme.subtleInk : AppTheme.surface)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 42)
                                    .background(settingsStore.isCheckingHealth ? AppTheme.surface : AppTheme.ink)
                                    .overlay(
                                        Rectangle()
                                            .stroke(AppTheme.border, lineWidth: AppTheme.retroBorderWidth)
                                    )
                                    .retroHardShadow()
                            }
                            .buttonStyle(.plain)
                            .disabled(settingsStore.isCheckingHealth)

                            Text(cloudHelpText)
                                .font(.system(size: 12, weight: .regular, design: .monospaced))
                                .foregroundStyle(AppTheme.subtleInk)

                            #if DEBUG
                            if settingsStore.isUsingDebugBackendOverride {
                                Button(AppStrings.current.useCloudDefault) {
                                    settingsStore.clearDebugBackendOverride()
                                }
                                .buttonStyle(.plain)
                                .font(.system(size: 13, weight: .bold, design: .monospaced))
                                .foregroundStyle(AppTheme.ink)
                            }
                            #endif
                        }
                        .padding(16)
                    }
                    .background(AppTheme.surface)
                    .overlay(
                        Rectangle()
                            .stroke(AppTheme.border, lineWidth: AppTheme.retroBorderWidth)
                    )
                    .retroHardShadow()

                    // Status window
                    VStack(spacing: 0) {
                        RetroTitleBar(label: AppStrings.current.status)

                        VStack(spacing: 0) {
                            statusRow(title: AppStrings.current.backend, value: backendStateLabel)
                            RetroDivider()
                            statusRow(title: AppStrings.current.asr, value: asrStateLabel)
                            RetroDivider()
                            statusRow(title: AppStrings.current.ai, value: llmStateLabel)
                            RetroDivider()
                            statusRow(title: AppStrings.current.sync, value: syncValue)
                        }
                        .padding(16)
                    }
                    .background(AppTheme.surface)
                    .overlay(
                        Rectangle()
                            .stroke(AppTheme.border, lineWidth: AppTheme.retroBorderWidth)
                    )
                    .retroHardShadow()
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
                Text(AppStrings.current.devSettingsTitle)
                    .font(.system(size: 28, weight: .bold, design: .monospaced))
                    .foregroundStyle(AppTheme.ink)

                Text(AppStrings.current.developerDiagnostics)
                    .font(.system(size: 13, weight: .regular, design: .monospaced))
                    .foregroundStyle(AppTheme.subtleInk)
            }

            Spacer()

            AppGlassCircleButton(systemName: "chevron.left", accessibilityLabel: AppStrings.current.back, size: 40) {
                dismiss()
            }
        }
    }

    private func settingsRow(systemName: String, title: String, value: String) -> some View {
        HStack(spacing: 10) {
            RetroIconBadge(systemName: systemName, size: 28, symbolSize: 11)

            Text(title)
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundStyle(AppTheme.ink)

            Spacer()

            Text(value)
                .font(.system(size: 13, weight: .regular, design: .monospaced))
                .foregroundStyle(AppTheme.subtleInk)
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 11)
    }

    private func statusRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundStyle(AppTheme.ink)

            Spacer()

            Text(value)
                .font(.system(size: 13, weight: .regular, design: .monospaced))
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
        return message.isEmpty ? AppStrings.current.syncIdleState : message
    }

    private var backendStateLabel: String {
        switch settingsStore.backendCapabilityStatus {
        case .checking:
            return AppStrings.current.checking
        case .standby:
            return AppStrings.current.standby
        case .ready:
            return settingsStore.backendStatusMessage
        case .offline, .unavailable:
            return settingsStore.backendStatusMessage
        }
    }

    private var asrStateLabel: String {
        switch settingsStore.asrCapabilityStatus {
        case .checking:
            return AppStrings.current.checking
        case .standby:
            return AppStrings.current.standby
        case .ready, .unavailable, .offline:
            return settingsStore.asrStatusMessage
        }
    }

    private var llmStateLabel: String {
        switch settingsStore.llmCapabilityStatus {
        case .checking:
            return AppStrings.current.checking
        case .standby:
            return AppStrings.current.standby
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
