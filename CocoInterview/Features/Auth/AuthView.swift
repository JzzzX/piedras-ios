import SwiftUI

struct AuthView: View {
    @Environment(AuthStore.self) private var authStore

    var body: some View {
        ZStack {
            AppGlassBackdrop()

            VStack(spacing: 24) {
                Spacer(minLength: 0)
                header
                oauthCard

                if let errorMessage = currentErrorMessage {
                    errorBanner(errorMessage)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 32)
        }
        .sheet(item: oauthSessionBinding) { session in
            AuthOAuthSheet(session: session)
        }
    }

    private var header: some View {
        Text(AppStrings.current.appTitle)
            .font(AppTheme.titleFont(size: 34))
            .foregroundStyle(AppTheme.brandInk)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var oauthCard: some View {
        VStack(spacing: 12) {
            oauthButton(
                title: AppStrings.current.authWechatAction,
                fill: Color(hex: 0x2E6B4A),
                action: { startOAuth(.wechat) }
            )

            oauthButton(
                title: AppStrings.current.authGoogleAction,
                fill: AppTheme.surface,
                foreground: AppTheme.brandInk,
                action: { startOAuth(.google) }
            )
        }
    }

    private var isSubmitting: Bool {
        authStore.phase == .submitting || authStore.phase == .restoring
    }

    private var oauthSessionBinding: Binding<AuthWebSession?> {
        Binding(
            get: { authStore.activeOAuthSession },
            set: { newValue in
                if newValue == nil {
                    authStore.cancelOAuth()
                }
            }
        )
    }

    private var currentErrorMessage: String? {
        guard let message = authStore.lastErrorMessage?.trimmingCharacters(in: .whitespacesAndNewlines),
              !message.isEmpty else {
            return nil
        }
        return message
    }

    private func oauthButton(
        title: String,
        fill: Color,
        foreground: Color = AppTheme.surface,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .font(AppTheme.bodyFont(size: 15, weight: .semibold))
                    .foregroundStyle(foreground)

                Spacer(minLength: 12)

                Image(systemName: "arrow.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(foreground.opacity(0.8))
            }
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity)
            .frame(height: 46)
            .background(fill)
            .overlay(
                Rectangle()
                    .stroke(AppTheme.brandInk, lineWidth: AppTheme.retroBorderWidth)
            )
            .retroHardShadow()
        }
        .buttonStyle(.plain)
        .disabled(isSubmitting)
        .opacity(isSubmitting ? 0.7 : 1)
    }

    private func errorBanner(_ message: String) -> some View {
        Text(message)
            .font(AppTheme.bodyFont(size: 12, weight: .semibold))
            .foregroundStyle(Color(red: 0.68, green: 0.16, blue: 0.14))
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppTheme.surface)
            .overlay(
                Rectangle()
                    .stroke(AppTheme.selectedChromeBorder, lineWidth: AppTheme.subtleBorderWidth)
            )
    }

    private func startOAuth(_ provider: OAuthProvider) {
        guard !isSubmitting else { return }

        Task {
            _ = await authStore.beginOAuth(provider: provider)
        }
    }
}
