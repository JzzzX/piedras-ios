import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SettingsStore.self) private var settingsStore
    @Environment(MeetingStore.self) private var meetingStore

    var body: some View {
        @Bindable var settingsStore = settingsStore

        ZStack {
            AppGlassBackdrop()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    header

                    if settingsStore.requiresInitialBackendSetup {
                        setupBanner
                    }

                    AppGlassCard(cornerRadius: 34, style: .regular, padding: 20, shadowOpacity: 0.08) {
                        VStack(spacing: 0) {
                            settingsRow(systemName: "mic.fill", title: "Recording", value: "16 kHz")
                            AppGlassDivider(inset: 42)
                            settingsRow(systemName: "waveform", title: "Transcript", value: transcriptValue)
                            AppGlassDivider(inset: 42)
                            settingsRow(systemName: "sparkles", title: "AI", value: aiValue)
                            AppGlassDivider(inset: 42)
                            settingsRow(systemName: "internaldrive", title: "Storage", value: "On Device")
                        }
                    }

                    AppGlassCard(cornerRadius: 34, style: .regular, padding: 20, shadowOpacity: 0.08) {
                        VStack(alignment: .leading, spacing: 14) {
                            Text("Backend Setup")
                                .font(.headline)
                                .foregroundStyle(AppTheme.ink)

                            TextField("http://192.168.x.x:3000", text: $settingsStore.backendBaseURLString)
                                .textInputAutocapitalization(.never)
                                .keyboardType(.URL)
                                .autocorrectionDisabled()
                                .padding(.horizontal, 14)
                                .frame(height: 50)
                                .background {
                                    AppGlassSurface(cornerRadius: 18, style: .clear, shadowOpacity: 0.03)
                                }
                                .accessibilityIdentifier("BackendURLField")

                            HStack(spacing: 10) {
                                Button("Use localhost") {
                                    settingsStore.backendBaseURLString = SettingsStore.simulatorLoopbackBaseURLString
                                }
                                .buttonStyle(.plain)
                                .font(.footnote.weight(.medium))
                                .foregroundStyle(AppTheme.ink)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .background {
                                    AppGlassSurface(cornerRadius: 18, style: .clear, shadowOpacity: 0.03)
                                }

                                Spacer()
                            }

                            AppGlassCapsuleButton(
                                prominent: canCheckBackend,
                                minHeight: 48,
                                action: {
                                    Task {
                                        await meetingStore.checkBackendHealth(force: true)
                                    }
                                }
                            ) {
                                Text(settingsStore.isCheckingHealth ? "Checking..." : "Check Connection")
                                    .font(.headline)
                                    .foregroundStyle(canCheckBackend && !settingsStore.isCheckingHealth ? .white : AppTheme.subtleInk)
                            }
                            .disabled(!canCheckBackend || settingsStore.isCheckingHealth)

                            Text(serverHelpText)
                                .font(.footnote)
                                .foregroundStyle(AppTheme.subtleInk)
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

                Text("Backend & status")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.subtleInk)
            }

            Spacer()

            if !settingsStore.requiresInitialBackendSetup {
                AppGlassCircleButton(systemName: "xmark", accessibilityLabel: "关闭") {
                    dismiss()
                }
            }
        }
    }

    private var setupBanner: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "macbook.and.iphone")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(AppTheme.ink)

            VStack(alignment: .leading, spacing: 4) {
                Text("Connect your Mac backend first.")
                    .font(.headline)
                    .foregroundStyle(AppTheme.ink)

                Text("AI and live transcription stay off until a server address is configured.")
                    .font(.footnote)
                    .foregroundStyle(AppTheme.subtleInk)
            }
        }
        .padding(16)
        .background {
            AppGlassSurface(cornerRadius: 22, style: .clear, shadowOpacity: 0.03)
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

    private var canCheckBackend: Bool {
        settingsStore.hasConfiguredBackendURL
    }

    private var serverHelpText: String {
        switch settingsStore.backendConnectionState {
        case .unconfigured:
            return "On iPhone, use your Mac LAN address. On Simulator, localhost also works."
        case .configuredUnchecked:
            return "Save an address, then run Check Connection."
        case .reachable:
            return "Current server: \(settingsStore.trimmedBackendBaseURLString)"
        case .unreachable:
            if let lastSuccessful = settingsStore.lastSuccessfulBackendURLString, !lastSuccessful.isEmpty {
                return "Last working server: \(lastSuccessful)"
            }
            return "The configured server is offline or unreachable."
        }
    }

    private var syncValue: String {
        let message = settingsStore.syncStatusMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        return message.isEmpty ? "Idle" : message
    }

    private var transcriptValue: String {
        switch settingsStore.backendConnectionState {
        case .unconfigured:
            return "Setup"
        case .configuredUnchecked:
            return "Needs Check"
        case .reachable:
            return settingsStore.asrReady ? "Ready" : "Unavailable"
        case .unreachable:
            return "Offline"
        }
    }

    private var aiValue: String {
        switch settingsStore.backendConnectionState {
        case .unconfigured:
            return "Setup"
        case .configuredUnchecked:
            return "Needs Check"
        case .reachable:
            return settingsStore.llmReady ? "Ready" : "Unavailable"
        case .unreachable:
            return "Offline"
        }
    }

    private var backendStateLabel: String {
        switch settingsStore.backendConnectionState {
        case .unconfigured:
            return "Setup required"
        case .configuredUnchecked:
            return "Not checked"
        case .reachable:
            return settingsStore.backendStatusMessage
        case .unreachable:
            return "Offline"
        }
    }

    private var asrStateLabel: String {
        switch settingsStore.backendConnectionState {
        case .unconfigured:
            return "Set backend first"
        case .configuredUnchecked:
            return "Check connection first"
        case .reachable, .unreachable:
            return settingsStore.asrStatusMessage
        }
    }

    private var llmStateLabel: String {
        switch settingsStore.backendConnectionState {
        case .unconfigured:
            return "Set backend first"
        case .configuredUnchecked:
            return "Check connection first"
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
