import SwiftUI

struct DeveloperSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SettingsStore.self) private var settingsStore
    @Environment(MeetingStore.self) private var meetingStore
    #if DEBUG
    @State private var debugBackendDraft = ""
    #endif

    var body: some View {
        ZStack {
            AppGlassBackdrop()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    header

                    VStack(alignment: .leading, spacing: 8) {
                        SectionLabel(title: AppStrings.current.general)

                        VStack(spacing: 0) {
                            settingsRow(systemName: "network", title: AppStrings.current.service, value: settingsStore.serviceModeLabel)
                            ThinDivider(inset: 42)
                            settingsRow(systemName: "mic.fill", title: AppStrings.current.recordingQuality, value: "16 kHz")
                            ThinDivider(inset: 42)
                            settingsRow(systemName: "internaldrive", title: AppStrings.current.storage, value: AppStrings.current.onDevice)
                            ThinDivider(inset: 42)
                            settingsRow(systemName: "app.badge", title: AppStrings.current.version, value: AppEnvironment.versionDescription)
                        }
                        .padding(16)
                        .softCard()
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        SectionLabel(title: AppStrings.current.ai)

                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 12) {
                                RetroIconBadge(systemName: "waveform.badge.magnifyingglass", size: 28, symbolSize: 11)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(AppStrings.current.experimentalAudioAINotesToggle)
                                        .font(AppTheme.bodyFont(size: 14, weight: .semibold))
                                        .foregroundStyle(AppTheme.brandInk)

                                    Text(AppStrings.current.experimentalAudioAINotesHelp)
                                        .font(AppTheme.bodyFont(size: 12))
                                        .foregroundStyle(AppTheme.subtleInk)
                                        .multilineTextAlignment(.leading)

                                    Text(AppStrings.current.experimentalAudioAINotesFutureNotice)
                                        .font(AppTheme.bodyFont(size: 11))
                                        .foregroundStyle(AppTheme.subtleInk)
                                        .multilineTextAlignment(.leading)
                                }

                                Spacer()

                                Text(AppStrings.current.comingSoonShort)
                                    .font(AppTheme.dataFont(size: 12))
                                    .foregroundStyle(AppTheme.subtleInk)
                            }
                            .padding(.vertical, 4)
                            .opacity(0.72)
                        }
                        .padding(16)
                        .softCard()
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        SectionLabel(title: AppStrings.current.cloud)

                        VStack(alignment: .leading, spacing: 12) {
                            Text(AppEnvironment.cloudName)
                                .font(AppTheme.bodyFont(size: 17, weight: .semibold))
                                .foregroundStyle(AppTheme.brandInk)

                            Text(settingsStore.backendDisplayURLString)
                                .font(AppTheme.dataFont(size: 13))
                                .foregroundStyle(AppTheme.subtleInk)
                                .textSelection(.enabled)

                            Button {
                                Task {
                                    await meetingStore.checkBackendHealth(force: true)
                                }
                            } label: {
                                Text(settingsStore.isCheckingHealth ? AppStrings.current.checking : AppStrings.current.refreshStatus)
                                    .font(AppTheme.bodyFont(size: 14, weight: .semibold))
                                    .foregroundStyle(settingsStore.isCheckingHealth ? AppTheme.subtleInk : AppTheme.primaryActionForeground)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 42)
                                    .background(settingsStore.isCheckingHealth ? AppTheme.selectedChromeFill : AppTheme.primaryActionFill)
                                    .overlay(
                                        Rectangle()
                                            .stroke(settingsStore.isCheckingHealth ? AppTheme.selectedChromeBorder : AppTheme.brandInk, lineWidth: AppTheme.retroBorderWidth)
                                    )
                                    .retroHardShadow()
                            }
                            .buttonStyle(.plain)
                            .disabled(settingsStore.isCheckingHealth)

                            Text(cloudHelpText)
                                .font(AppTheme.bodyFont(size: 12))
                                .foregroundStyle(AppTheme.subtleInk)

                            #if DEBUG
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Debug backend override")
                                    .font(AppTheme.bodyFont(size: 12, weight: .semibold))
                                    .foregroundStyle(AppTheme.subtleInk)

                                TextField("https://api.example.com", text: $debugBackendDraft)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                                    .keyboardType(.URL)
                                    .font(AppTheme.dataFont(size: 13))
                                    .padding(.horizontal, 10)
                                    .frame(height: 40)
                                    .background(AppTheme.surface)
                                    .overlay(
                                        Rectangle()
                                            .stroke(AppTheme.subtleBorderColor, lineWidth: AppTheme.subtleBorderWidth)
                                    )

                                HStack(spacing: 10) {
                                    Button("应用地址") {
                                        settingsStore.applyDebugBackendOverride(debugBackendDraft)
                                        Task {
                                            await meetingStore.checkBackendHealth(force: true)
                                        }
                                    }
                                    .buttonStyle(.plain)
                                    .font(AppTheme.bodyFont(size: 13, weight: .semibold))
                                    .foregroundStyle(AppTheme.brandInk)

                                    if settingsStore.isUsingDebugBackendOverride {
                                        Button(AppStrings.current.useCloudDefault) {
                                            debugBackendDraft = AppEnvironment.productionBackendBaseURLString
                                            settingsStore.clearDebugBackendOverride()
                                        }
                                        .buttonStyle(.plain)
                                        .font(AppTheme.bodyFont(size: 13, weight: .semibold))
                                        .foregroundStyle(AppTheme.brandInk)
                                    }
                                }
                            }

                            if settingsStore.isUsingDebugBackendOverride {
                                Text("Using override: \(settingsStore.backendDisplayURLString)")
                                    .font(AppTheme.dataFont(size: 12))
                                    .foregroundStyle(AppTheme.subtleInk)
                            }
                            #endif
                        }
                        .padding(16)
                        .softCard()
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        SectionLabel(title: AppStrings.current.status)

                        VStack(spacing: 0) {
                            statusRow(title: AppStrings.current.backend, value: backendStateLabel)
                            ThinDivider()
                            statusRow(title: AppStrings.current.asr, value: asrStateLabel)
                            ThinDivider()
                            statusRow(title: AppStrings.current.ai, value: llmStateLabel)
                            ThinDivider()
                            statusRow(title: AppStrings.current.recentSync, value: syncValue)
                        }
                        .padding(16)
                        .softCard()
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        SectionLabel(title: AppStrings.current.sync)

                        VStack(alignment: .leading, spacing: 12) {
                            statusRow(title: AppStrings.current.recentSync, value: syncValue)
                            ThinDivider(inset: 0)
                            statusRow(title: AppStrings.current.syncDetail, value: syncDetailValue)
                            ThinDivider(inset: 0)
                            statusRow(title: AppStrings.current.lastFailure, value: formatted(syncDate: settingsStore.syncLastFailureAt))
                            ThinDivider(inset: 0)
                            statusRow(title: AppStrings.current.nextRetry, value: formatted(syncDate: settingsStore.syncNextRetryAt))
                            ThinDivider(inset: 0)
                            statusRow(title: AppStrings.current.lastSuccess, value: formatted(syncDate: settingsStore.lastSuccessfulSyncAt))

                            Button {
                                Task {
                                    await meetingStore.repairCloudState()
                                }
                            } label: {
                                Text(settingsStore.isSyncing ? AppStrings.current.checking : AppStrings.current.syncRepairAction)
                                    .font(AppTheme.bodyFont(size: 14, weight: .semibold))
                                    .foregroundStyle(settingsStore.isSyncing ? AppTheme.subtleInk : AppTheme.surface)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 42)
                                    .background(settingsStore.isSyncing ? AppTheme.surface : AppTheme.ink)
                                    .overlay(
                                        Rectangle()
                                            .stroke(AppTheme.border, lineWidth: AppTheme.retroBorderWidth)
                                    )
                                    .retroHardShadow()
                            }
                            .buttonStyle(.plain)
                            .disabled(settingsStore.isSyncing)
                        }
                        .padding(16)
                        .softCard()
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 32)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .task {
            #if DEBUG
            if debugBackendDraft.isEmpty {
                debugBackendDraft = settingsStore.isUsingDebugBackendOverride
                    ? settingsStore.debugBackendBaseURLString
                    : AppEnvironment.productionBackendBaseURLString
            }
            #endif
            await meetingStore.checkBackendHealth(force: false)
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text(AppStrings.current.devSettingsTitle)
                    .font(AppTheme.titleFont(size: 28, weight: .bold))
                    .foregroundStyle(AppTheme.brandInk)

                Text(AppStrings.current.developerDiagnostics)
                    .font(AppTheme.bodyFont(size: 13))
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
                .font(AppTheme.bodyFont(size: 14, weight: .semibold))
                .foregroundStyle(AppTheme.brandInk)

            Spacer()

            Text(value)
                .font(AppTheme.dataFont(size: 13))
                .foregroundStyle(AppTheme.subtleInk)
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 11)
    }

    private func statusRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .font(AppTheme.bodyFont(size: 14, weight: .semibold))
                .foregroundStyle(AppTheme.brandInk)

            Spacer()

            Text(value)
                .font(AppTheme.dataFont(size: 13))
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

    private var syncDetailValue: String {
        let message = settingsStore.syncDetailMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        return message.isEmpty ? AppStrings.current.notAvailableShort : message
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

    private func formatted(syncDate: Date?) -> String {
        guard let syncDate else {
            return AppStrings.current.notAvailableShort
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: AppStrings.currentLanguage == .chinese ? "zh_CN" : "en_US_POSIX")
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: syncDate)
    }
}
