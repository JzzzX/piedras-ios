import SwiftUI

struct AuthView: View {
    @Environment(AuthStore.self) private var authStore

    @State private var email = ""
    @State private var password = ""

    var body: some View {
        ZStack {
            AppGlassBackdrop()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    formCard
                }
                .padding(.horizontal, 16)
                .padding(.top, 24)
                .padding(.bottom, 32)
            }
        }
    }

    private var header: some View {
        Text(AppStrings.current.appTitle)
            .font(AppTheme.bodyFont(size: 30, weight: .bold))
            .foregroundStyle(AppTheme.ink)
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .softCard()
    }

    private var formCard: some View {
        VStack(alignment: .leading, spacing: 14) {
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

            Text(AppStrings.current.authSingleStepHint)
                .font(AppTheme.bodyFont(size: 12))
                .foregroundStyle(AppTheme.subtleInk)

            if let infoMessage = currentInfoMessage {
                infoBanner(infoMessage)
            }

            if authStore.phase == .awaitingEmailVerification {
                verificationBanner
            }

            if let errorMessage = currentErrorMessage {
                Text(errorMessage)
                    .font(AppTheme.bodyFont(size: 12, weight: .semibold))
                    .foregroundStyle(Color(red: 0.68, green: 0.16, blue: 0.14))
            }

            Button(action: submit) {
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

    private var normalizedEmail: String? {
        email.nilIfBlank
    }

    private var normalizedPassword: String? {
        password.nilIfBlank
    }

    private var isSubmitting: Bool {
        authStore.phase == .submitting || authStore.phase == .restoring
    }

    private var isFormReady: Bool {
        normalizedEmail != nil && normalizedPassword != nil
    }

    private var primaryActionTitle: String {
        isSubmitting ? AppStrings.current.processing : AppStrings.current.authSingleStepAction
    }

    private var currentInfoMessage: String? {
        authStore.lastInfoMessage?.nilIfBlank
    }

    private var currentErrorMessage: String? {
        authStore.lastErrorMessage?.nilIfBlank
    }

    private var verificationEmail: String? {
        authStore.pendingVerificationEmail?.nilIfBlank ?? normalizedEmail
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

    private var verificationBanner: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(AppStrings.current.authVerificationPendingTitle)
                .font(AppTheme.bodyFont(size: 12, weight: .semibold))
                .foregroundStyle(AppTheme.ink)

            Text(AppStrings.current.authVerificationPendingMessage(email: verificationEmail))
                .font(AppTheme.bodyFont(size: 12))
                .foregroundStyle(AppTheme.subtleInk)
        }
        .padding(12)
        .background(AppTheme.surface)
        .overlay(
            Rectangle()
                .stroke(AppTheme.subtleBorderColor, lineWidth: AppTheme.subtleBorderWidth)
        )
    }

    private func infoBanner(_ message: String) -> some View {
        Text(message)
            .font(AppTheme.bodyFont(size: 12, weight: .semibold))
            .foregroundStyle(AppTheme.ink)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppTheme.surface)
            .overlay(
                Rectangle()
                    .stroke(AppTheme.subtleBorderColor, lineWidth: AppTheme.subtleBorderWidth)
            )
    }

    private func submit() {
        guard !isSubmitting,
              let email = normalizedEmail,
              let password = normalizedPassword else { return }

        Task {
            _ = await authStore.authenticate(email: email, password: password)
        }
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
