import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SettingsStore.self) private var settingsStore
    @Environment(MeetingStore.self) private var meetingStore

    @State private var showsDeveloperSettings = false

    var body: some View {
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
                            settingsRow(
                                systemName: "waveform",
                                title: "Transcript",
                                value: settingsStore.asrReady ? "Ready" : "Unavailable"
                            )
                        }
                    }

                    AppGlassCard(cornerRadius: 34, style: .regular, padding: 20, shadowOpacity: 0.08) {
                        VStack(spacing: 0) {
                            settingsRow(
                                systemName: "sparkles",
                                title: "AI Notes",
                                value: settingsStore.apiReachable ? "Ready" : "Offline"
                            )
                            AppGlassDivider(inset: 42)
                            settingsRow(
                                systemName: "arrow.triangle.2.circlepath",
                                title: "Sync",
                                value: syncValue
                            )
                            AppGlassDivider(inset: 42)
                            settingsRow(
                                systemName: "info.circle",
                                title: "Version",
                                value: versionLabel
                            )
                            .contentShape(Rectangle())
                            .onLongPressGesture(minimumDuration: 0.8) {
                                showsDeveloperSettings = true
                            }
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
        .sheet(isPresented: $showsDeveloperSettings) {
            NavigationStack {
                DeveloperSettingsView()
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
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

    private var syncValue: String {
        let message = settingsStore.syncStatusMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        return message.isEmpty ? "Idle" : message
    }

    private var versionLabel: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }
}

private struct DeveloperSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SettingsStore.self) private var settingsStore
    @Environment(MeetingStore.self) private var meetingStore

    var body: some View {
        @Bindable var settingsStore = settingsStore

        ZStack {
            AppGlassBackdrop()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    HStack {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Developer")
                                .font(.system(size: 34, weight: .regular, design: .serif))
                                .foregroundStyle(AppTheme.ink)

                            Text("Internal")
                                .font(.subheadline)
                                .foregroundStyle(AppTheme.subtleInk)
                        }

                        Spacer()

                        AppGlassCircleButton(systemName: "xmark", accessibilityLabel: "关闭") {
                            dismiss()
                        }
                    }

                    AppGlassCard(cornerRadius: 32, style: .regular, padding: 20, shadowOpacity: 0.08) {
                        VStack(alignment: .leading, spacing: 14) {
                            Text("Backend")
                                .font(.headline)
                                .foregroundStyle(AppTheme.ink)

                            TextField("http://127.0.0.1:3000", text: $settingsStore.backendBaseURLString)
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
                                Text(settingsStore.isCheckingHealth ? "Checking..." : "Check Connection")
                                    .font(.headline)
                                    .foregroundStyle(settingsStore.isCheckingHealth ? AppTheme.subtleInk : .white)
                            }
                            .disabled(settingsStore.isCheckingHealth)
                        }
                    }

                    AppGlassCard(cornerRadius: 32, style: .regular, padding: 20, shadowOpacity: 0.08) {
                        VStack(spacing: 0) {
                            developerStatusRow(title: "Backend", value: backendStateLabel)
                            AppGlassDivider(inset: 0)
                            developerStatusRow(title: "ASR", value: settingsStore.asrStatusMessage)
                            AppGlassDivider(inset: 0)
                            developerStatusRow(title: "Workspace", value: settingsStore.workspaceStatusMessage)
                        }
                    }

                    AppGlassCard(cornerRadius: 32, style: .regular, padding: 20, shadowOpacity: 0.08) {
                        VStack(alignment: .leading, spacing: 14) {
                            Text("Sync")
                                .font(.headline)
                                .foregroundStyle(AppTheme.ink)

                            AppGlassCapsuleButton(
                                prominent: !settingsStore.isSyncing,
                                minHeight: 48,
                                action: {
                                    Task {
                                        await meetingStore.syncAllMeetings()
                                    }
                                }
                            ) {
                                Text(settingsStore.isSyncing ? "Syncing..." : "Sync Now")
                                    .font(.headline)
                                    .foregroundStyle(settingsStore.isSyncing ? AppTheme.subtleInk : .white)
                            }
                            .disabled(settingsStore.isSyncing)

                            if !settingsStore.syncStatusMessage.isEmpty {
                                Text(settingsStore.syncStatusMessage)
                                    .font(.footnote)
                                    .foregroundStyle(AppTheme.subtleInk)
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 40)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    private func developerStatusRow(title: String, value: String) -> some View {
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

    private var backendStateLabel: String {
        if settingsStore.lastHealthCheckAt == nil {
            return "Not checked"
        }

        return settingsStore.apiReachable ? settingsStore.backendStatusMessage : "Offline"
    }
}
