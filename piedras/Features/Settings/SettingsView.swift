import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SettingsStore.self) private var settingsStore
    @Environment(MeetingStore.self) private var meetingStore

    var body: some View {
        @Bindable var settingsStore = settingsStore

        ZStack {
            AppTheme.pageGradient
                .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    HStack {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Settings")
                                .font(.system(size: 36, weight: .regular, design: .serif))
                                .foregroundStyle(AppTheme.ink)

                            Text("Keep the app lightweight. Only the backend path and sync health stay visible.")
                                .font(.subheadline)
                                .foregroundStyle(AppTheme.subtleInk)
                        }

                        Spacer()

                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.headline.weight(.semibold))
                                .foregroundStyle(AppTheme.ink)
                                .frame(width: 40, height: 40)
                                .background(AppTheme.surface, in: Circle())
                                .overlay {
                                    Circle()
                                        .stroke(AppTheme.border.opacity(0.7), lineWidth: 1)
                                }
                        }
                        .buttonStyle(.plain)
                    }

                    settingsCard(title: "Backend") {
                        VStack(alignment: .leading, spacing: 12) {
                            TextField("http://127.0.0.1:3000", text: $settingsStore.backendBaseURLString)
                                .textInputAutocapitalization(.never)
                                .keyboardType(.URL)
                                .autocorrectionDisabled()
                                .padding(.horizontal, 14)
                                .frame(height: 50)
                                .background(AppTheme.backgroundSecondary, in: RoundedRectangle(cornerRadius: 18, style: .continuous))

                            Button(settingsStore.isCheckingHealth ? "Checking..." : "Check connection") {
                                Task {
                                    await meetingStore.checkBackendHealth(force: true)
                                }
                            }
                            .buttonStyle(.plain)
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(AppTheme.ink, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                            .disabled(settingsStore.isCheckingHealth)
                        }
                    }

                    settingsCard(title: "Status") {
                        VStack(spacing: 12) {
                            statusRow(title: "Backend", value: backendStateLabel)
                            statusRow(title: "ASR", value: settingsStore.asrReady ? "Ready" : "Unavailable")
                            statusRow(title: "Last sync", value: settingsStore.syncStatusMessage.isEmpty ? "Idle" : settingsStore.syncStatusMessage)
                        }
                    }

                    settingsCard(title: "Sync") {
                        VStack(alignment: .leading, spacing: 12) {
                            Button(settingsStore.isSyncing ? "Syncing..." : "Sync now") {
                                Task {
                                    await meetingStore.syncAllMeetings()
                                }
                            }
                            .buttonStyle(.plain)
                            .font(.headline)
                            .foregroundStyle(AppTheme.ink)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(AppTheme.backgroundSecondary, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                            .disabled(settingsStore.isSyncing)

                            Text("Hidden workspace bootstrap remains internal. Audio files are treated as transient processing artifacts and are cleaned after successful sync.")
                                .font(.footnote)
                                .foregroundStyle(AppTheme.subtleInk)
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

    private func settingsCard<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.headline)
                .foregroundStyle(AppTheme.ink)

            content()
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.surface, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(AppTheme.border.opacity(0.55), lineWidth: 1)
        }
    }

    private func statusRow(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.subtleInk)
                .textCase(.uppercase)

            Text(value)
                .font(.body)
                .foregroundStyle(AppTheme.ink)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(AppTheme.backgroundSecondary, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var backendStateLabel: String {
        if settingsStore.lastHealthCheckAt == nil {
            return "Not checked"
        }

        return settingsStore.apiReachable ? settingsStore.backendStatusMessage : "Offline"
    }
}
