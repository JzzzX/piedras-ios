import Foundation
import Observation

enum AuthPhase: Equatable {
    case unauthenticated
    case restoring
    case submitting
    case awaitingOneTimeCode
    case awaitingEmailVerification
    case needsPasswordSetup
    case authenticated
}

@MainActor
@Observable
final class AuthStore {
    private let apiClient: any AuthNetworking
    private let tokenStore: any AuthTokenStoring
    private let snapshotStore: any AuthSessionSnapshotStoring

    var phase: AuthPhase = .unauthenticated
    var currentUser: RemoteAuthUser?
    var currentWorkspace: RemoteWorkspace?
    var hasResolvedInitialSession = false
    var isSessionValidated = false
    var isValidatingCachedSession = false
    var lastErrorMessage: String?
    var lastInfoMessage: String?
    var pendingVerificationEmail: String?
    var pendingOneTimeCodeEmail: String?
    var pendingOneTimeCodeIntent: EmailOTPIntent?
    var activeOAuthSession: AuthWebSession?
    var logoutBlockedMessage: String?
    var logoutBlockMessageProvider: (() -> String?)?
    var didAuthenticate: ((RemoteAuthUser, RemoteWorkspace) async -> Void)?
    var didUnauthenticate: (() async -> Void)?
    private var pendingPasswordSetupResponse: RemoteAuthResponse?

    init(
        apiClient: any AuthNetworking,
        tokenStore: any AuthTokenStoring,
        snapshotStore: (any AuthSessionSnapshotStoring)? = nil
    ) {
        self.apiClient = apiClient
        self.tokenStore = tokenStore
        self.snapshotStore = snapshotStore ?? DiscardingAuthSessionSnapshotStore()
    }

    var isAuthenticated: Bool {
        phase == .authenticated
    }

    @discardableResult
    func handleAuthCallback(url: URL) async -> Bool {
        guard isSupportedAuthCallbackURL(url) else {
            return false
        }

        let parameters = authCallbackParameters(from: url)
        guard let accessToken = parameters["access_token"]?.nilIfBlank,
              let refreshToken = parameters["refresh_token"]?.nilIfBlank else {
            return false
        }

        resetTransientMessages()
        phase = .restoring

        tokenStore.sessionToken = accessToken
        tokenStore.refreshToken = refreshToken

        do {
            let sessionState = try await apiClient.fetchAuthSession()
            await applyAuthenticatedSession(
                user: sessionState.user,
                workspace: sessionState.workspace,
                session: sessionState.session
            )
            return true
        } catch {
            lastErrorMessage = error.localizedDescription
            await clearSession()
            return false
        }
    }

    @discardableResult
    func beginOAuth(provider: OAuthProvider) async -> Bool {
        phase = .submitting
        lastErrorMessage = nil
        lastInfoMessage = nil
        logoutBlockedMessage = nil

        do {
            let authorizationURL = try await apiClient.fetchOAuthAuthorizationURL(provider: provider)
            activeOAuthSession = AuthWebSession(
                provider: provider,
                authorizationURL: authorizationURL
            )
            phase = .unauthenticated
            return true
        } catch {
            activeOAuthSession = nil
            lastErrorMessage = error.localizedDescription
            phase = .unauthenticated
            return false
        }
    }

    func cancelOAuth() {
        activeOAuthSession = nil
        if phase == .submitting {
            phase = .unauthenticated
        }
    }

    @discardableResult
    func completeOAuthCallbackPayload(_ payload: Data) async -> Bool {
        phase = .submitting
        lastErrorMessage = nil
        lastInfoMessage = nil
        logoutBlockedMessage = nil

        do {
            let response = try await apiClient.completeOAuthCallbackPayload(payload)
            persistSession(response.session)
            activeOAuthSession = nil
            await applyAuthenticatedSession(
                user: response.user,
                workspace: response.workspace,
                session: response.session
            )
            return true
        } catch {
            lastErrorMessage = error.localizedDescription
            phase = .unauthenticated
            return false
        }
    }

    func bootstrapSession() async {
        resetTransientMessages()

        if await hydrateCachedSessionIfPossible() {
            await validateCachedSession()
            return
        }

        await performSessionRestore(silentValidation: false)
    }

    @discardableResult
    func hydrateCachedSessionIfPossible() async -> Bool {
        guard tokenStore.refreshToken?.nilIfBlank != nil,
              let snapshot = snapshotStore.snapshot else {
            return false
        }

        currentUser = snapshot.user
        currentWorkspace = snapshot.workspace
        pendingVerificationEmail = nil
        pendingOneTimeCodeEmail = nil
        pendingOneTimeCodeIntent = nil
        activeOAuthSession = nil
        pendingPasswordSetupResponse = nil
        logoutBlockedMessage = nil
        phase = .authenticated
        hasResolvedInitialSession = true
        isSessionValidated = false
        isValidatingCachedSession = true
        await didAuthenticate?(snapshot.user, snapshot.workspace)
        return true
    }

    func validateCachedSession() async {
        guard isValidatingCachedSession else { return }
        await performSessionRestore(silentValidation: true)
    }

    func restoreSession() async {
        await performSessionRestore(silentValidation: false)
    }

    @discardableResult
    func login(email: String, password: String) async -> Bool {
        beginCredentialSubmission()

        do {
            let response = try await apiClient.login(email: email, password: password)
            persistSession(response.session)
            await applyAuthenticatedSession(
                user: response.user,
                workspace: response.workspace,
                session: response.session
            )
            return true
        } catch {
            lastErrorMessage = error.localizedDescription
            phase = .unauthenticated
            return false
        }
    }

    @discardableResult
    func authenticate(email: String, password: String) async -> Bool {
        beginCredentialSubmission()

        do {
            let registration = try await apiClient.register(
                email: email,
                password: password,
                displayName: nil
            )

            if registration.requiresEmailVerification {
                pendingVerificationEmail = registration.verificationEmail ?? email
                lastInfoMessage = "验证邮件已发送，请先完成邮箱验证。"
                phase = .awaitingEmailVerification
                return false
            }

            persistSession(registration.session)
            await applyAuthenticatedSession(
                user: registration.user,
                workspace: registration.workspace,
                session: registration.session
            )
            return true
        } catch {
            guard shouldFallbackToLogin(after: error) else {
                lastErrorMessage = error.localizedDescription
                phase = .unauthenticated
                return false
            }
        }

        do {
            let response = try await apiClient.login(email: email, password: password)
            persistSession(response.session)
            await applyAuthenticatedSession(
                user: response.user,
                workspace: response.workspace,
                session: response.session
            )
            return true
        } catch {
            lastErrorMessage = error.localizedDescription
            phase = .unauthenticated
            return false
        }
    }

    @discardableResult
    func sendEmailOTP(email: String, intent: EmailOTPIntent) async -> Bool {
        phase = .submitting
        lastErrorMessage = nil
        lastInfoMessage = nil
        pendingVerificationEmail = nil
        logoutBlockedMessage = nil
        pendingPasswordSetupResponse = nil

        do {
            let normalizedEmail = email.nilIfBlank ?? email
            try await apiClient.sendEmailOTP(email: normalizedEmail, intent: intent)
            pendingOneTimeCodeEmail = normalizedEmail
            pendingOneTimeCodeIntent = intent
            lastInfoMessage = intent == .login
                ? "验证码已发送，请检查邮箱并完成登录。"
                : "验证码已发送，验证后即可完成注册。"
            phase = .awaitingOneTimeCode
            return true
        } catch {
            lastErrorMessage = error.localizedDescription
            phase = .unauthenticated
            return false
        }
    }

    @discardableResult
    func loginWithEmailOTP(email: String, token: String) async -> Bool {
        phase = .submitting
        lastErrorMessage = nil
        lastInfoMessage = nil
        pendingVerificationEmail = nil
        logoutBlockedMessage = nil
        pendingPasswordSetupResponse = nil

        do {
            let response = try await apiClient.loginWithEmailOTP(email: email, token: token)
            persistSession(response.session)
            await applyAuthenticatedSession(
                user: response.user,
                workspace: response.workspace,
                session: response.session
            )
            return true
        } catch {
            lastErrorMessage = error.localizedDescription
            phase = .awaitingOneTimeCode
            return false
        }
    }

    @discardableResult
    func registerWithEmailOTP(email: String, token: String) async -> Bool {
        phase = .submitting
        lastErrorMessage = nil
        lastInfoMessage = nil
        pendingVerificationEmail = nil
        pendingOneTimeCodeEmail = email.nilIfBlank ?? email
        pendingOneTimeCodeIntent = .register
        logoutBlockedMessage = nil

        do {
            let response = try await apiClient.registerWithEmailOTP(email: email, token: token)
            persistSession(response.session)
            pendingPasswordSetupResponse = response
            lastInfoMessage = "注册成功，可选设置密码，之后也能继续用邮箱验证码登录。"
            phase = .needsPasswordSetup
            return true
        } catch {
            lastErrorMessage = error.localizedDescription
            phase = .awaitingOneTimeCode
            return false
        }
    }

    @discardableResult
    func register(
        email: String,
        password: String,
        displayName: String? = nil
    ) async -> Bool {
        phase = .submitting
        lastErrorMessage = nil
        lastInfoMessage = nil
        pendingVerificationEmail = nil
        pendingOneTimeCodeEmail = nil
        pendingOneTimeCodeIntent = nil
        logoutBlockedMessage = nil
        pendingPasswordSetupResponse = nil

        do {
            let response = try await apiClient.register(
                email: email,
                password: password,
                displayName: displayName
            )
            if response.requiresEmailVerification {
                pendingVerificationEmail = response.verificationEmail ?? email
                lastInfoMessage = "验证邮件已发送，请先完成邮箱验证。"
                phase = .awaitingEmailVerification
                return false
            }
            persistSession(response.session)
            await applyAuthenticatedSession(
                user: response.user,
                workspace: response.workspace,
                session: response.session
            )
            return true
        } catch {
            lastErrorMessage = error.localizedDescription
            phase = .unauthenticated
            return false
        }
    }

    @discardableResult
    func skipPasswordSetup() async -> Bool {
        guard let response = pendingPasswordSetupResponse else {
            return false
        }

        resetTransientMessages()
        await applyAuthenticatedSession(
            user: response.user,
            workspace: response.workspace,
            session: response.session
        )
        return true
    }

    @discardableResult
    func completePasswordSetup(password: String) async -> Bool {
        guard pendingPasswordSetupResponse != nil else {
            return false
        }

        phase = .submitting
        lastErrorMessage = nil
        lastInfoMessage = nil
        logoutBlockedMessage = nil

        do {
            try await apiClient.setPassword(password: password)
            return await skipPasswordSetup()
        } catch {
            lastErrorMessage = error.localizedDescription
            phase = .needsPasswordSetup
            return false
        }
    }

    @discardableResult
    func logout(force: Bool = false) async -> Bool {
        lastErrorMessage = nil
        lastInfoMessage = nil

        if !force,
           let message = logoutBlockMessageProvider?()?.nilIfBlank {
            logoutBlockedMessage = message
            return false
        }

        logoutBlockedMessage = nil

        do {
            try await apiClient.logout()
        } catch {
            lastErrorMessage = error.localizedDescription
            return false
        }

        await clearSession()
        return true
    }

    @discardableResult
    func requestPasswordReset(email: String) async -> Bool {
        phase = .submitting
        lastErrorMessage = nil
        lastInfoMessage = nil

        do {
            try await apiClient.requestPasswordReset(email: email)
            lastInfoMessage = "重置密码邮件已发送，请检查邮箱。"
            if phase == .submitting {
                phase = pendingVerificationEmail?.nilIfBlank != nil ? .awaitingEmailVerification : .unauthenticated
            }
            return true
        } catch {
            lastErrorMessage = error.localizedDescription
            phase = pendingVerificationEmail?.nilIfBlank != nil ? .awaitingEmailVerification : .unauthenticated
            return false
        }
    }

    @discardableResult
    func resendVerificationEmail(email: String) async -> Bool {
        phase = .submitting
        lastErrorMessage = nil
        lastInfoMessage = nil

        do {
            try await apiClient.resendVerificationEmail(email: email)
            pendingVerificationEmail = email.nilIfBlank ?? pendingVerificationEmail
            lastInfoMessage = "验证邮件已重新发送，请检查邮箱。"
            phase = .awaitingEmailVerification
            return true
        } catch {
            lastErrorMessage = error.localizedDescription
            phase = pendingVerificationEmail?.nilIfBlank != nil ? .awaitingEmailVerification : .unauthenticated
            return false
        }
    }

    private func applyAuthenticatedSession(
        user: RemoteAuthUser,
        workspace: RemoteWorkspace,
        session: RemoteAuthSession
    ) async {
        currentUser = user
        currentWorkspace = workspace
        pendingVerificationEmail = nil
        pendingOneTimeCodeEmail = nil
        pendingOneTimeCodeIntent = nil
        pendingPasswordSetupResponse = nil
        lastInfoMessage = nil
        snapshotStore.snapshot = CachedAuthSessionSnapshot(
            user: user,
            workspace: workspace,
            expiresAt: session.expiresAt,
            savedAt: .now
        )
        phase = .authenticated
        hasResolvedInitialSession = true
        isSessionValidated = true
        isValidatingCachedSession = false
        await didAuthenticate?(user, workspace)
    }

    private func clearSession() async {
        tokenStore.clearTokens()
        snapshotStore.clearSnapshot()
        currentUser = nil
        currentWorkspace = nil
        pendingVerificationEmail = nil
        pendingOneTimeCodeEmail = nil
        pendingOneTimeCodeIntent = nil
        activeOAuthSession = nil
        pendingPasswordSetupResponse = nil
        phase = .unauthenticated
        hasResolvedInitialSession = true
        isSessionValidated = false
        isValidatingCachedSession = false
        await didUnauthenticate?()
    }

    private func persistSession(_ session: RemoteAuthSession) {
        tokenStore.sessionToken = session.token
        tokenStore.refreshToken = session.refreshToken
    }

    private func performSessionRestore(silentValidation: Bool) async {
        resetTransientMessages()

        guard tokenStore.sessionToken?.nilIfBlank != nil || tokenStore.refreshToken?.nilIfBlank != nil else {
            await clearSession()
            return
        }

        if !silentValidation {
            phase = .restoring
        } else {
            isValidatingCachedSession = true
        }

        if let sessionToken = tokenStore.sessionToken?.nilIfBlank {
            do {
                let sessionState = try await apiClient.fetchAuthSession()
                tokenStore.sessionToken = sessionToken
                await applyAuthenticatedSession(
                    user: sessionState.user,
                    workspace: sessionState.workspace,
                    session: sessionState.session
                )
                return
            } catch {
                if tokenStore.refreshToken?.nilIfBlank == nil {
                    lastErrorMessage = error.localizedDescription
                    await clearSession()
                    return
                }
            }
        }

        guard let refreshToken = tokenStore.refreshToken?.nilIfBlank else {
            await clearSession()
            return
        }

        do {
            let response = try await apiClient.refreshAuthSession(refreshToken: refreshToken)
            persistSession(response.session)
            await applyAuthenticatedSession(
                user: response.user,
                workspace: response.workspace,
                session: response.session
            )
        } catch {
            lastErrorMessage = error.localizedDescription
            await clearSession()
        }
    }

    private func resetTransientMessages() {
        lastErrorMessage = nil
        lastInfoMessage = nil
        logoutBlockedMessage = nil
    }

    private func beginCredentialSubmission() {
        phase = .submitting
        lastErrorMessage = nil
        lastInfoMessage = nil
        pendingVerificationEmail = nil
        pendingOneTimeCodeEmail = nil
        pendingOneTimeCodeIntent = nil
        logoutBlockedMessage = nil
        pendingPasswordSetupResponse = nil
    }

    private func shouldFallbackToLogin(after error: Error) -> Bool {
        let normalizedMessage = error.localizedDescription
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        return normalizedMessage.contains("已注册")
            || normalizedMessage.contains("already registered")
            || normalizedMessage.contains("already exists")
            || normalizedMessage.contains("email exists")
    }

    private func isSupportedAuthCallbackURL(_ url: URL) -> Bool {
        url.scheme?.caseInsensitiveCompare("cocointerview") == .orderedSame
            && url.host?.caseInsensitiveCompare("auth") == .orderedSame
            && url.path == "/callback"
    }

    private func authCallbackParameters(from url: URL) -> [String: String] {
        var combined: [String: String] = [:]

        if let components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            for item in components.queryItems ?? [] {
                combined[item.name] = item.value
            }
        }

        if let fragment = url.fragment,
           let fragmentComponents = URLComponents(string: "https://callback.local?\(fragment)") {
            for item in fragmentComponents.queryItems ?? [] {
                combined[item.name] = item.value
            }
        }

        return combined
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
