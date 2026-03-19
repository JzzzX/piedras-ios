import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SettingsStore.self) private var settingsStore
    @Environment(MeetingStore.self) private var meetingStore

    @State private var showDeveloperSettings = false

    var body: some View {
        ZStack {
            AppGlassBackdrop()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    header

                    // Language picker
                    VStack(spacing: 0) {
                        RetroTitleBar(label: AppStrings.current.languageLabel)

                        VStack(spacing: 12) {
                            languagePicker
                        }
                        .padding(16)
                    }
                    .background(AppTheme.surface)
                    .overlay(
                        Rectangle()
                            .stroke(AppTheme.border, lineWidth: AppTheme.retroBorderWidth)
                    )
                    .retroHardShadow()

                    // About section
                    VStack(spacing: 0) {
                        RetroTitleBar(label: AppStrings.current.about)

                        VStack(spacing: 0) {
                            aboutRow(title: AppStrings.current.version, value: AppEnvironment.versionDescription)
                            RetroDivider(inset: 0)
                            aboutRow(title: AppStrings.current.serviceMode, value: settingsStore.serviceModeLabel)
                        }
                        .padding(16)
                    }
                    .background(AppTheme.surface)
                    .overlay(
                        Rectangle()
                            .stroke(AppTheme.border, lineWidth: AppTheme.retroBorderWidth)
                    )
                    .retroHardShadow()

                    // Developer mode navigation
                    NavigationLink(destination: DeveloperSettingsView()) {
                        HStack(spacing: 12) {
                            RetroIconBadge(systemName: "wrench.and.screwdriver", size: 28, symbolSize: 11)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(AppStrings.current.developerMode)
                                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                                    .foregroundStyle(AppTheme.ink)

                                Text(AppStrings.current.developerDiagnostics)
                                    .font(.system(size: 12, weight: .regular, design: .monospaced))
                                    .foregroundStyle(AppTheme.subtleInk)
                            }

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(AppTheme.subtleInk)
                        }
                        .padding(16)
                        .background(AppTheme.surface)
                        .overlay(
                            Rectangle()
                                .stroke(AppTheme.border, lineWidth: AppTheme.retroBorderWidth)
                        )
                        .retroHardShadow()
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 32)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text(AppStrings.current.settingsTitle)
                    .font(.system(size: 28, weight: .bold, design: .monospaced))
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
                        .font(.system(size: 15, weight: .bold, design: .monospaced))
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
                .stroke(AppTheme.border, lineWidth: AppTheme.retroBorderWidth)
        )
    }

    private func aboutRow(title: String, value: String) -> some View {
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
}
