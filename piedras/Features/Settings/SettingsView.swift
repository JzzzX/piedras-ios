import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AuthStore.self) private var authStore
    @Environment(SettingsStore.self) private var settingsStore
    @Environment(MeetingStore.self) private var meetingStore

    @State private var showForceLogoutConfirmation = false

    var body: some View {
        ZStack {
            AppGlassBackdrop()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    header

                    if let currentUser = authStore.currentUser {
                        VStack(alignment: .leading, spacing: 8) {
                            SectionLabel(title: AppStrings.current.accountSectionTitle)

                            VStack(alignment: .leading, spacing: 12) {
                                aboutRow(title: AppStrings.current.authEmailLabel, value: currentUser.email)

                                if let workspace = authStore.currentWorkspace {
                                    ThinDivider(inset: 0)
                                    aboutRow(title: AppStrings.current.authWorkspaceLabel, value: workspace.name)
                                }

                                Button {
                                    attemptLogout()
                                } label: {
                                    Text(
                                        authStore.phase == .submitting
                                            ? AppStrings.current.processing
                                            : AppStrings.current.logoutAction
                                    )
                                    .font(AppTheme.bodyFont(size: 14, weight: .semibold))
                                    .foregroundStyle(AppTheme.surface)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 42)
                                    .background(Color(red: 0.68, green: 0.16, blue: 0.14))
                                    .overlay(
                                        Rectangle()
                                            .stroke(AppTheme.border, lineWidth: AppTheme.retroBorderWidth)
                                    )
                                    .retroHardShadow()
                                }
                                .buttonStyle(.plain)
                                .disabled(authStore.phase == .submitting)
                            }
                            .padding(16)
                            .softCard()
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        SectionLabel(title: AppStrings.current.languageLabel)

                        VStack(spacing: 12) {
                            languagePicker
                        }
                        .padding(16)
                        .softCard()
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        SectionLabel(title: AppStrings.current.about)

                        VStack(spacing: 0) {
                            aboutRow(title: AppStrings.current.version, value: AppEnvironment.versionDescription)
                            ThinDivider(inset: 0)
                            aboutRow(title: AppStrings.current.serviceMode, value: settingsStore.serviceModeLabel)
                        }
                        .padding(16)
                        .softCard()
                    }

                    // Developer mode navigation
                    NavigationLink(destination: DeveloperSettingsView()) {
                        HStack(spacing: 12) {
                            RetroIconBadge(systemName: "wrench.and.screwdriver", size: 28, symbolSize: 11)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(AppStrings.current.developerMode)
                                    .font(AppTheme.bodyFont(size: 14, weight: .semibold))
                                    .foregroundStyle(AppTheme.ink)

                                Text(AppStrings.current.developerDiagnostics)
                                    .font(AppTheme.bodyFont(size: 12))
                                    .foregroundStyle(AppTheme.subtleInk)
                            }

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(AppTheme.subtleInk)
                        }
                        .padding(16)
                        .softCard()
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 32)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .confirmationDialog(
            AppStrings.current.authForceLogoutTitle,
            isPresented: $showForceLogoutConfirmation,
            titleVisibility: .visible
        ) {
            Button(AppStrings.current.authForceLogoutAction, role: .destructive) {
                Task {
                    _ = await authStore.logout(force: true)
                    dismiss()
                }
            }
            Button(AppStrings.current.cancel, role: .cancel) {}
        } message: {
            Text(authStore.logoutBlockedMessage ?? AppStrings.current.authForceLogoutMessage)
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text(AppStrings.current.settingsTitle)
                    .font(AppTheme.bodyFont(size: 28, weight: .bold))
                    .foregroundStyle(AppTheme.ink)
            }

            Spacer()

            AppGlassCircleButton(systemName: "xmark", accessibilityLabel: AppStrings.current.close, size: 40) {
                dismiss()
            }
        }
    }

    @MainActor
    private var languagePicker: some View {
        @Bindable var store = settingsStore
        return HStack(spacing: 0) {
            ForEach(AppLanguage.allCases) { lang in
                Button {
                    withAnimation(.easeOut(duration: 0.18)) {
                        settingsStore.appLanguage = lang
                    }
                } label: {
                    Text(lang.displayName)
                        .font(AppTheme.bodyFont(size: 15, weight: .semibold))
                        .foregroundStyle(settingsStore.appLanguage == lang ? AppTheme.surface : AppTheme.ink)
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                        .background(settingsStore.appLanguage == lang ? AppTheme.ink : AppTheme.surface)
                }
                .buttonStyle(.plain)
            }
        }
        .overlay(
            Rectangle()
                .stroke(AppTheme.subtleBorderColor, lineWidth: AppTheme.subtleBorderWidth)
        )
    }

    private func aboutRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .font(AppTheme.bodyFont(size: 14, weight: .semibold))
                .foregroundStyle(AppTheme.ink)

            Spacer()

            Text(value)
                .font(AppTheme.dataFont(size: 13))
                .foregroundStyle(AppTheme.subtleInk)
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 11)
    }

    private func attemptLogout() {
        Task {
            let didLogout = await authStore.logout()
            if didLogout {
                dismiss()
            } else if authStore.logoutBlockedMessage != nil {
                showForceLogoutConfirmation = true
            }
        }
    }
}
