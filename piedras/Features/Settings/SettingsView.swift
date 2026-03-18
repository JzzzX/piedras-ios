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

                    AppGlassCard(cornerRadius: 34, style: .regular, padding: 20, shadowOpacity: 0.08) {
                        VStack(spacing: 0) {
                            settingsRow(systemName: "mic.fill", title: "Recording", value: "16 kHz")
                            AppGlassDivider(inset: 42)
                            settingsRow(systemName: "internaldrive", title: "Storage", value: "On Device")
                            AppGlassDivider(inset: 42)
                            settingsRow(systemName: "waveform", title: "Transcript", value: transcriptValue)
                            AppGlassDivider(inset: 42)
                            settingsRow(systemName: "sparkles", title: "AI", value: aiValue)
                        }
                    }

                    AppGlassCard(cornerRadius: 34, style: .regular, padding: 20, shadowOpacity: 0.08) {
                        VStack(alignment: .leading, spacing: 14) {
                            Text("Server")
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

                            AppGlassCapsuleButton(
                                prominent: !settingsStore.isCheckingHealth,
                                minHeight: 48,
                                action: {
                                    Task {
                                        await meetingStore.checkBackendHealth(force: true)
                                    }
                                }
                            ) {
                                Text(settingsStore.isCheckingHealth ? "Checking..." : "Check")
                                    .font(.headline)
                                    .foregroundStyle(settingsStore.isCheckingHealth ? AppTheme.subtleInk : .white)
                            }
                            .disabled(settingsStore.isCheckingHealth)
                        }
                    }

                    AppGlassCard(cornerRadius: 34, style: .regular, padding: 20, shadowOpacity: 0.08) {
                        VStack(spacing: 0) {
                            statusRow(title: "Backend", value: backendStateLabel)
                            AppGlassDivider(inset: 0)
                            statusRow(title: "ASR", value: settingsStore.asrStatusMessage)
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

                Text("Piedras")
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

    private var syncValue: String {
        let message = settingsStore.syncStatusMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        return message.isEmpty ? "Idle" : message
    }

    private var transcriptValue: String {
        if !settingsStore.apiReachable, settingsStore.lastHealthCheckAt != nil {
            return "Offline"
        }

        return settingsStore.asrReady ? "Ready" : "Unavailable"
    }

    private var aiValue: String {
        if !settingsStore.apiReachable, settingsStore.lastHealthCheckAt != nil {
            return "Offline"
        }

        return settingsStore.llmReady ? "Ready" : "Unavailable"
    }

    private var backendStateLabel: String {
        if settingsStore.lastHealthCheckAt == nil {
            return "Not checked"
        }

        return settingsStore.apiReachable ? settingsStore.backendStatusMessage : "Offline"
    }

    private var llmStateLabel: String {
        if !settingsStore.apiReachable, settingsStore.lastHealthCheckAt != nil {
            return "Offline"
        }

        guard settingsStore.llmReady else {
            return settingsStore.llmStatusMessage
        }

        let provider = settingsStore.llmProvider.capitalized
        let preset = settingsStore.llmPreset.flatMap { $0.isEmpty ? nil : $0 }
        let model = settingsStore.llmModel.flatMap { $0.isEmpty ? nil : $0 }
        return [provider, preset, model].compactMap { $0 }.joined(separator: " · ")
    }
}
