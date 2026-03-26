import SwiftUI

private enum AuthScreenMode: String, CaseIterable, Identifiable {
    case login
    case register

    var id: String { rawValue }
}

struct AuthView: View {
    @Environment(AuthStore.self) private var authStore
    @Environment(SettingsStore.self) private var settingsStore

    @State private var mode: AuthScreenMode = .login
    @State private var email = ""
    @State private var password = ""
    @State private var inviteCode = ""
    @State private var displayName = ""

    var body: some View {
        ZStack {
            AppGlassBackdrop()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    modePicker
                    formCard
                    footerCard
                }
                .padding(.horizontal, 16)
                .padding(.top, 24)
                .padding(.bottom, 32)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(AppStrings.current.appTitle)
                .font(AppTheme.bodyFont(size: 30, weight: .bold))
                .foregroundStyle(AppTheme.ink)

            Text(AppStrings.current.authSubtitle)
                .font(AppTheme.bodyFont(size: 14))
                .foregroundStyle(AppTheme.subtleInk)

            Text(settingsStore.backendDisplayURLString)
                .font(AppTheme.dataFont(size: 12))
                .foregroundStyle(AppTheme.subtleInk)
                .textSelection(.enabled)
        }
        .padding(20)
        .softCard()
    }

    private var modePicker: some View {
        HStack(spacing: 0) {
            authModeButton(.login)
            authModeButton(.register)
        }
        .overlay(
            Rectangle()
                .stroke(AppTheme.subtleBorderColor, lineWidth: AppTheme.subtleBorderWidth)
        )
    }

    private var formCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionLabel(title: AppStrings.current.accountSectionTitle)

            VStack(alignment: .leading, spacing: 10) {
                formField(
                    title: AppStrings.current.authEmailLabel,
                    placeholder: "you@example.com",
                    text: $email,
                    textContentType: .username,
                    keyboardType: .emailAddress
                )

                secureFormField(
                    title: AppStrings.current.authPasswordLabel,
                    placeholder: AppStrings.current.authPasswordPlaceholder,
                    text: $password
                )

                if mode == .register {
                    formField(
                        title: AppStrings.current.authInviteCodeLabel,
                        placeholder: AppStrings.current.authInviteCodePlaceholder,
                        text: $inviteCode,
                        textContentType: nil,
                        keyboardType: .asciiCapable
                    )

                    formField(
                        title: AppStrings.current.authDisplayNameLabel,
                        placeholder: AppStrings.current.authDisplayNamePlaceholder,
                        text: $displayName,
                        textContentType: .name,
                        keyboardType: .default
                    )
                }
            }

            if let errorMessage = authStore.lastErrorMessage?.trimmingCharacters(in: .whitespacesAndNewlines),
               !errorMessage.isEmpty {
                Text(errorMessage)
                    .font(AppTheme.bodyFont(size: 12, weight: .semibold))
                    .foregroundStyle(Color(red: 0.68, green: 0.16, blue: 0.14))
            }

            Button {
                submit()
            } label: {
                Text(primaryActionTitle)
                    .font(AppTheme.bodyFont(size: 15, weight: .semibold))
                    .foregroundStyle(AppTheme.surface)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(AppTheme.ink)
                    .overlay(
                        Rectangle()
                            .stroke(AppTheme.border, lineWidth: AppTheme.retroBorderWidth)
                    )
                    .retroHardShadow()
            }
            .buttonStyle(.plain)
            .disabled(isSubmitting || !isFormReady)
            .opacity(isFormReady ? 1 : 0.65)
        }
        .padding(20)
        .softCard()
    }

    private var footerCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(AppStrings.current.authResetHint)
                .font(AppTheme.bodyFont(size: 12))
                .foregroundStyle(AppTheme.subtleInk)

            Text(AppStrings.current.authSwitchHint)
                .font(AppTheme.bodyFont(size: 12))
                .foregroundStyle(AppTheme.subtleInk)
        }
        .padding(16)
        .softCard()
    }

    private var primaryActionTitle: String {
        if isSubmitting {
            return AppStrings.current.processing
        }

        switch mode {
        case .login:
            return AppStrings.current.authLoginAction
        case .register:
            return AppStrings.current.authRegisterAction
        }
    }

    private var isSubmitting: Bool {
        authStore.phase == .submitting
    }

    private var isFormReady: Bool {
        let hasEmail = !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasPassword = !password.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasInviteCode = !inviteCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        switch mode {
        case .login:
            return hasEmail && hasPassword
        case .register:
            return hasEmail && hasPassword && hasInviteCode
        }
    }

    private func authModeButton(_ candidate: AuthScreenMode) -> some View {
        Button {
            mode = candidate
            authStore.lastErrorMessage = nil
        } label: {
            Text(candidate == .login ? AppStrings.current.authLoginTab : AppStrings.current.authRegisterTab)
                .font(AppTheme.bodyFont(size: 15, weight: .semibold))
                .foregroundStyle(mode == candidate ? AppTheme.surface : AppTheme.ink)
                .frame(maxWidth: .infinity)
                .frame(height: 42)
                .background(mode == candidate ? AppTheme.ink : AppTheme.surface)
        }
        .buttonStyle(.plain)
    }

    private func formField(
        title: String,
        placeholder: String,
        text: Binding<String>,
        textContentType: UITextContentType?,
        keyboardType: UIKeyboardType
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(AppTheme.bodyFont(size: 12, weight: .semibold))
                .foregroundStyle(AppTheme.subtleInk)

            TextField(placeholder, text: text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textContentType(textContentType)
                .keyboardType(keyboardType)
                .font(AppTheme.dataFont(size: 13))
                .padding(.horizontal, 10)
                .frame(height: 42)
                .background(AppTheme.surface)
                .overlay(
                    Rectangle()
                        .stroke(AppTheme.subtleBorderColor, lineWidth: AppTheme.subtleBorderWidth)
                )
        }
    }

    private func secureFormField(
        title: String,
        placeholder: String,
        text: Binding<String>
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(AppTheme.bodyFont(size: 12, weight: .semibold))
                .foregroundStyle(AppTheme.subtleInk)

            SecureField(placeholder, text: text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textContentType(.password)
                .font(AppTheme.dataFont(size: 13))
                .padding(.horizontal, 10)
                .frame(height: 42)
                .background(AppTheme.surface)
                .overlay(
                    Rectangle()
                        .stroke(AppTheme.subtleBorderColor, lineWidth: AppTheme.subtleBorderWidth)
                )
        }
    }

    private func submit() {
        guard !isSubmitting else { return }

        Task {
            switch mode {
            case .login:
                _ = await authStore.login(email: email, password: password)
            case .register:
                _ = await authStore.register(
                    email: email,
                    password: password,
                    inviteCode: inviteCode,
                    displayName: displayName.nilIfBlank
                )
            }
        }
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
