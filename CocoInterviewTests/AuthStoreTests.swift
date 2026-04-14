import Foundation
import Testing
@testable import CocoInterview

@MainActor
private final class StubAuthClient: AuthNetworking {
    var loginResult: Result<RemoteAuthResponse, Error> = .failure(APIClientError.invalidResponse)
    var registerResult: Result<RemoteAuthResponse, Error> = .failure(APIClientError.invalidResponse)
    var emailOTPLoginResult: Result<RemoteAuthResponse, Error> = .failure(APIClientError.invalidResponse)
    var emailOTPRegisterResult: Result<RemoteAuthResponse, Error> = .failure(APIClientError.invalidResponse)
    var refreshResult: Result<RemoteAuthResponse, Error> = .failure(APIClientError.invalidResponse)
    var sessionResult: Result<RemoteAuthSessionState, Error> = .failure(APIClientError.invalidResponse)
    var fetchAuthSessionCallCount = 0
    var logoutCallCount = 0
    var requestedPasswordResetEmail: String?
    var requestedVerificationEmail: String?
    var requestedOTPEmail: String?
    var requestedOTPIntent: EmailOTPIntent?
    var updatedPassword: String?
    var loginCalls: [(email: String, password: String)] = []
    var registerCalls: [(email: String, password: String, displayName: String?)] = []

    func login(email: String, password: String) async throws -> RemoteAuthResponse {
        loginCalls.append((email: email, password: password))
        return try loginResult.get()
    }

    func register(
        email: String,
        password: String,
        displayName: String?
    ) async throws -> RemoteAuthResponse {
        registerCalls.append((email: email, password: password, displayName: displayName))
        return try registerResult.get()
    }

    func sendEmailOTP(email: String, intent: EmailOTPIntent) async throws {
        requestedOTPEmail = email
        requestedOTPIntent = intent
    }

    func loginWithEmailOTP(email: String, token: String) async throws -> RemoteAuthResponse {
        try emailOTPLoginResult.get()
    }

    func registerWithEmailOTP(email: String, token: String) async throws -> RemoteAuthResponse {
        try emailOTPRegisterResult.get()
    }

    func setPassword(password: String) async throws {
        updatedPassword = password
    }

    func refreshAuthSession(refreshToken: String) async throws -> RemoteAuthResponse {
        try refreshResult.get()
    }

    func fetchAuthSession() async throws -> RemoteAuthSessionState {
        fetchAuthSessionCallCount += 1
        return try sessionResult.get()
    }

    func logout() async throws {
        logoutCallCount += 1
    }

    func requestPasswordReset(email: String) async throws {
        requestedPasswordResetEmail = email
    }

    func resendVerificationEmail(email: String) async throws {
        requestedVerificationEmail = email
    }
}

@MainActor
private final class InMemoryAuthTokenStoreTestsDouble: AuthTokenStoring {
    var sessionToken: String?
    var refreshToken: String?

    init(sessionToken: String? = nil, refreshToken: String? = nil) {
        self.sessionToken = sessionToken
        self.refreshToken = refreshToken
    }

    func clearTokens() {
        sessionToken = nil
        refreshToken = nil
    }
}

@MainActor
private final class InMemoryAuthSessionSnapshotStoreTestsDouble: AuthSessionSnapshotStoring {
    var snapshot: CachedAuthSessionSnapshot?

    init(snapshot: CachedAuthSessionSnapshot? = nil) {
        self.snapshot = snapshot
    }

    func clearSnapshot() {
        snapshot = nil
    }
}

struct AuthStoreTests {
    @MainActor
    @Test
    func hydrateCachedSessionAuthenticatesImmediatelyWhenRefreshTokenExists() async {
        let apiClient = StubAuthClient()
        let tokenStore = InMemoryAuthTokenStoreTestsDouble(refreshToken: "refresh-token")
        let snapshotStore = InMemoryAuthSessionSnapshotStoreTestsDouble(
            snapshot: CachedAuthSessionSnapshot(
                user: .init(id: "cached-user", email: "cached@example.com"),
                workspace: .init(id: "cached-workspace", name: "Cached"),
                expiresAt: Date(timeIntervalSince1970: 2_000),
                savedAt: Date(timeIntervalSince1970: 1_500)
            )
        )
        let store = AuthStore(
            apiClient: apiClient,
            tokenStore: tokenStore,
            snapshotStore: snapshotStore
        )

        let hydrated = await store.hydrateCachedSessionIfPossible()

        #expect(hydrated == true)
        #expect(store.phase == .authenticated)
        #expect(store.currentUser?.email == "cached@example.com")
        #expect(store.currentWorkspace?.id == "cached-workspace")
        #expect(store.hasResolvedInitialSession == true)
        #expect(store.isSessionValidated == false)
        #expect(store.isValidatingCachedSession == true)
    }

    @MainActor
    @Test
    func bootstrapSessionPersistsSnapshotAfterNetworkRestore() async {
        let apiClient = StubAuthClient()
        let tokenStore = InMemoryAuthTokenStoreTestsDouble(sessionToken: "session-token")
        let snapshotStore = InMemoryAuthSessionSnapshotStoreTestsDouble()
        let store = AuthStore(
            apiClient: apiClient,
            tokenStore: tokenStore,
            snapshotStore: snapshotStore
        )
        apiClient.sessionResult = .success(
            RemoteAuthSessionState(
                user: .init(id: "user-1", email: "test@example.com"),
                workspace: .init(id: "workspace-1", name: "椰子面试"),
                session: .init(expiresAt: Date(timeIntervalSince1970: 2_000))
            )
        )

        await store.bootstrapSession()

        #expect(store.phase == .authenticated)
        #expect(store.hasResolvedInitialSession == true)
        #expect(store.isSessionValidated == true)
        #expect(store.isValidatingCachedSession == false)
        #expect(snapshotStore.snapshot?.user.email == "test@example.com")
        #expect(snapshotStore.snapshot?.workspace.id == "workspace-1")
        #expect(snapshotStore.snapshot?.expiresAt == Date(timeIntervalSince1970: 2_000))
    }

    @MainActor
    @Test
    func validateCachedSessionClearsSnapshotWhenRefreshFails() async {
        let apiClient = StubAuthClient()
        let tokenStore = InMemoryAuthTokenStoreTestsDouble(
            sessionToken: "expired-token",
            refreshToken: "refresh-token"
        )
        let snapshotStore = InMemoryAuthSessionSnapshotStoreTestsDouble(
            snapshot: CachedAuthSessionSnapshot(
                user: .init(id: "cached-user", email: "cached@example.com"),
                workspace: .init(id: "cached-workspace", name: "Cached"),
                expiresAt: Date(timeIntervalSince1970: 2_000),
                savedAt: Date(timeIntervalSince1970: 1_500)
            )
        )
        let store = AuthStore(
            apiClient: apiClient,
            tokenStore: tokenStore,
            snapshotStore: snapshotStore
        )
        apiClient.sessionResult = .failure(APIClientError.requestFailed("expired"))
        apiClient.refreshResult = .failure(APIClientError.requestFailed("refresh failed"))

        let hydrated = await store.hydrateCachedSessionIfPossible()
        #expect(hydrated == true)

        await store.validateCachedSession()

        #expect(store.phase == .unauthenticated)
        #expect(store.currentUser == nil)
        #expect(store.currentWorkspace == nil)
        #expect(store.hasResolvedInitialSession == true)
        #expect(store.isSessionValidated == false)
        #expect(store.isValidatingCachedSession == false)
        #expect(tokenStore.sessionToken == nil)
        #expect(tokenStore.refreshToken == nil)
        #expect(snapshotStore.snapshot == nil)
    }

    @MainActor
    @Test
    func authenticateCreatesNewAccountWhenEmailIsNotRegistered() async {
        let apiClient = StubAuthClient()
        let tokenStore = InMemoryAuthTokenStoreTestsDouble()
        let store = AuthStore(apiClient: apiClient, tokenStore: tokenStore)
        apiClient.registerResult = .success(
            RemoteAuthResponse(
                user: .init(id: "user-new", email: "new@example.com"),
                workspace: .init(id: "workspace-new", name: "椰子面试"),
                session: .init(
                    token: "session-token",
                    refreshToken: "refresh-token",
                    expiresAt: Date(timeIntervalSince1970: 1_000)
                )
            )
        )

        let didAuthenticate = await store.authenticate(email: "new@example.com", password: "password-123")

        #expect(didAuthenticate == true)
        #expect(apiClient.registerCalls.count == 1)
        #expect(apiClient.loginCalls.isEmpty)
        #expect(store.phase == .authenticated)
        #expect(store.currentUser?.email == "new@example.com")
    }

    @MainActor
    @Test
    func authenticateFallsBackToLoginWhenAccountAlreadyExists() async {
        let apiClient = StubAuthClient()
        let tokenStore = InMemoryAuthTokenStoreTestsDouble()
        let store = AuthStore(apiClient: apiClient, tokenStore: tokenStore)
        apiClient.registerResult = .failure(APIClientError.requestFailed("该邮箱已注册"))
        apiClient.loginResult = .success(
            RemoteAuthResponse(
                user: .init(id: "user-existing", email: "existing@example.com"),
                workspace: .init(id: "workspace-existing", name: "椰子面试"),
                session: .init(
                    token: "session-token",
                    refreshToken: "refresh-token",
                    expiresAt: Date(timeIntervalSince1970: 1_000)
                )
            )
        )

        let didAuthenticate = await store.authenticate(email: "existing@example.com", password: "password-123")

        #expect(didAuthenticate == true)
        #expect(apiClient.registerCalls.count == 1)
        #expect(apiClient.loginCalls.count == 1)
        #expect(store.phase == .authenticated)
        #expect(store.currentUser?.email == "existing@example.com")
    }

    @MainActor
    @Test
    func authenticateShowsLoginErrorAfterExistingAccountFallbackFails() async {
        let apiClient = StubAuthClient()
        let tokenStore = InMemoryAuthTokenStoreTestsDouble()
        let store = AuthStore(apiClient: apiClient, tokenStore: tokenStore)
        apiClient.registerResult = .failure(APIClientError.requestFailed("该邮箱已注册"))
        apiClient.loginResult = .failure(APIClientError.requestFailed("邮箱或密码错误"))

        let didAuthenticate = await store.authenticate(email: "existing@example.com", password: "wrong-password")

        #expect(didAuthenticate == false)
        #expect(apiClient.registerCalls.count == 1)
        #expect(apiClient.loginCalls.count == 1)
        #expect(store.phase == .unauthenticated)
        #expect(store.lastErrorMessage == "邮箱或密码错误")
    }

    @MainActor
    @Test
    func restoreSessionWithoutTokenBecomesUnauthenticated() async {
        let apiClient = StubAuthClient()
        let tokenStore = InMemoryAuthTokenStoreTestsDouble()
        let store = AuthStore(apiClient: apiClient, tokenStore: tokenStore)

        await store.restoreSession()

        #expect(store.phase == .unauthenticated)
        #expect(store.currentUser == nil)
    }

    @MainActor
    @Test
    func loginPersistsTokenAndMarksStoreAuthenticated() async {
        let apiClient = StubAuthClient()
        let tokenStore = InMemoryAuthTokenStoreTestsDouble()
        let store = AuthStore(apiClient: apiClient, tokenStore: tokenStore)
        apiClient.loginResult = .success(
            RemoteAuthResponse(
                user: .init(id: "user-1", email: "test@example.com"),
                workspace: .init(id: "workspace-1", name: "椰子面试"),
                session: .init(
                    token: "session-token",
                    refreshToken: "refresh-token",
                    expiresAt: Date(timeIntervalSince1970: 1_000)
                )
            )
        )

        let didLogin = await store.login(email: "test@example.com", password: "password-123")

        #expect(didLogin == true)
        #expect(store.phase == .authenticated)
        #expect(store.currentUser?.email == "test@example.com")
        #expect(tokenStore.sessionToken == "session-token")
        #expect(tokenStore.refreshToken == "refresh-token")
    }

    @MainActor
    @Test
    func restoreSessionWithStoredTokenLoadsCurrentUser() async {
        let apiClient = StubAuthClient()
        let tokenStore = InMemoryAuthTokenStoreTestsDouble(sessionToken: "session-token")
        let store = AuthStore(apiClient: apiClient, tokenStore: tokenStore)
        apiClient.sessionResult = .success(
            RemoteAuthSessionState(
                user: .init(id: "user-1", email: "test@example.com"),
                workspace: .init(id: "workspace-1", name: "椰子面试"),
                session: .init(expiresAt: Date(timeIntervalSince1970: 2_000))
            )
        )

        await store.restoreSession()

        #expect(store.phase == .authenticated)
        #expect(store.currentUser?.email == "test@example.com")
        #expect(store.currentWorkspace?.id == "workspace-1")
        #expect(tokenStore.sessionToken == "session-token")
    }

    @MainActor
    @Test
    func restoreSessionFailureClearsStoredToken() async {
        let apiClient = StubAuthClient()
        let tokenStore = InMemoryAuthTokenStoreTestsDouble(
            sessionToken: "expired-token",
            refreshToken: "refresh-token"
        )
        let store = AuthStore(apiClient: apiClient, tokenStore: tokenStore)
        apiClient.sessionResult = .failure(APIClientError.requestFailed("expired"))

        await store.restoreSession()

        #expect(store.phase == .unauthenticated)
        #expect(store.currentUser == nil)
        #expect(tokenStore.sessionToken == nil)
        #expect(tokenStore.refreshToken == nil)
    }

    @MainActor
    @Test
    func loginInvokesDidAuthenticateCallback() async {
        let apiClient = StubAuthClient()
        let tokenStore = InMemoryAuthTokenStoreTestsDouble()
        let store = AuthStore(apiClient: apiClient, tokenStore: tokenStore)
        var callbackEmail: String?
        apiClient.loginResult = .success(
            RemoteAuthResponse(
                user: .init(id: "user-1", email: "test@example.com"),
                workspace: .init(id: "workspace-1", name: "椰子面试"),
                session: .init(
                    token: "session-token",
                    refreshToken: "refresh-token",
                    expiresAt: Date(timeIntervalSince1970: 1_000)
                )
            )
        )
        store.didAuthenticate = { user, _ in
            callbackEmail = user.email
        }

        let didLogin = await store.login(email: "test@example.com", password: "password-123")

        #expect(didLogin == true)
        #expect(callbackEmail == "test@example.com")
    }

    @MainActor
    @Test
    func forceLogoutInvokesDidUnauthenticateCallback() async {
        let apiClient = StubAuthClient()
        let tokenStore = InMemoryAuthTokenStoreTestsDouble(sessionToken: "session-token")
        let store = AuthStore(apiClient: apiClient, tokenStore: tokenStore)
        var callbackCount = 0
        store.currentUser = .init(id: "user-1", email: "test@example.com")
        store.currentWorkspace = .init(id: "workspace-1", name: "椰子面试")
        store.phase = .authenticated
        store.didUnauthenticate = {
            callbackCount += 1
        }

        let didLogout = await store.logout(force: true)

        #expect(didLogout == true)
        #expect(callbackCount == 1)
    }

    @MainActor
    @Test
    func logoutStopsWhenUnsyncedDataRequiresUserConfirmation() async {
        let apiClient = StubAuthClient()
        let tokenStore = InMemoryAuthTokenStoreTestsDouble(sessionToken: "session-token")
        let store = AuthStore(apiClient: apiClient, tokenStore: tokenStore)
        store.currentUser = .init(id: "user-1", email: "test@example.com")
        store.currentWorkspace = .init(id: "workspace-1", name: "椰子面试")
        store.phase = .authenticated
        store.logoutBlockMessageProvider = { "还有未同步数据" }

        let didLogout = await store.logout()

        #expect(didLogout == false)
        #expect(store.logoutBlockedMessage == "还有未同步数据")
        #expect(tokenStore.sessionToken == "session-token")
        #expect(apiClient.logoutCallCount == 0)
    }

    @MainActor
    @Test
    func forceLogoutClearsSessionEvenWhenLogoutIsBlocked() async {
        let apiClient = StubAuthClient()
        let tokenStore = InMemoryAuthTokenStoreTestsDouble(sessionToken: "session-token")
        let store = AuthStore(apiClient: apiClient, tokenStore: tokenStore)
        store.currentUser = .init(id: "user-1", email: "test@example.com")
        store.currentWorkspace = .init(id: "workspace-1", name: "椰子面试")
        store.phase = .authenticated
        store.logoutBlockMessageProvider = { "还有未同步数据" }

        let didLogout = await store.logout(force: true)

        #expect(didLogout == true)
        #expect(store.phase == .unauthenticated)
        #expect(store.currentUser == nil)
        #expect(tokenStore.sessionToken == nil)
        #expect(apiClient.logoutCallCount == 1)
    }

    @MainActor
    @Test
    func registerAwaitingEmailVerificationDoesNotAuthenticateTheStore() async {
        let apiClient = StubAuthClient()
        let tokenStore = InMemoryAuthTokenStoreTestsDouble()
        let store = AuthStore(apiClient: apiClient, tokenStore: tokenStore)
        apiClient.registerResult = .success(
            RemoteAuthResponse(
                user: .init(id: "user-verify", email: "verify@example.com"),
                workspace: .init(id: "workspace-verify", name: "椰子面试"),
                session: .init(token: nil, expiresAt: Date(timeIntervalSince1970: 1_000)),
                requiresEmailVerification: true,
                verificationEmail: "verify@example.com"
            )
        )

        let didRegister = await store.register(
            email: "verify@example.com",
            password: "password-123",
            displayName: "Verify User"
        )

        #expect(didRegister == false)
        #expect(store.phase == .awaitingEmailVerification)
        #expect(store.currentUser == nil)
        #expect(tokenStore.sessionToken == nil)
        #expect(store.pendingVerificationEmail == "verify@example.com")
    }

    @MainActor
    @Test
    func restoreSessionRefreshesWhenAccessTokenHasExpired() async {
        let apiClient = StubAuthClient()
        let tokenStore = InMemoryAuthTokenStoreTestsDouble(
            sessionToken: "expired-token",
            refreshToken: "refresh-token-1"
        )
        let store = AuthStore(apiClient: apiClient, tokenStore: tokenStore)
        apiClient.sessionResult = .failure(APIClientError.requestFailed("expired"))
        apiClient.refreshResult = .success(
            RemoteAuthResponse(
                user: .init(id: "user-refresh", email: "refresh@example.com"),
                workspace: .init(id: "workspace-refresh", name: "椰子面试"),
                session: .init(
                    token: "fresh-token",
                    refreshToken: "refresh-token-2",
                    expiresAt: Date(timeIntervalSince1970: 3_000)
                )
            )
        )

        await store.restoreSession()

        #expect(store.phase == .authenticated)
        #expect(store.currentUser?.email == "refresh@example.com")
        #expect(tokenStore.sessionToken == "fresh-token")
        #expect(tokenStore.refreshToken == "refresh-token-2")
    }

    @MainActor
    @Test
    func requestPasswordResetStoresInfoMessage() async {
        let apiClient = StubAuthClient()
        let tokenStore = InMemoryAuthTokenStoreTestsDouble()
        let store = AuthStore(apiClient: apiClient, tokenStore: tokenStore)

        let didSubmit = await store.requestPasswordReset(email: "reset@example.com")

        #expect(didSubmit == true)
        #expect(apiClient.requestedPasswordResetEmail == "reset@example.com")
        #expect(store.lastInfoMessage == "重置密码邮件已发送，请检查邮箱。")
    }

    @MainActor
    @Test
    func sendRegisterOTPTransitionsStoreToAwaitingOneTimeCode() async {
        let apiClient = StubAuthClient()
        let tokenStore = InMemoryAuthTokenStoreTestsDouble()
        let store = AuthStore(apiClient: apiClient, tokenStore: tokenStore)

        let didSubmit = await store.sendEmailOTP(email: "new@example.com", intent: .register)

        #expect(didSubmit == true)
        #expect(apiClient.requestedOTPEmail == "new@example.com")
        #expect(apiClient.requestedOTPIntent == .register)
        #expect(store.phase == .awaitingOneTimeCode)
        #expect(store.pendingOneTimeCodeEmail == "new@example.com")
        #expect(store.pendingOneTimeCodeIntent == .register)
    }

    @MainActor
    @Test
    func registerWithEmailOTPWaitsForOptionalPasswordSetup() async {
        let apiClient = StubAuthClient()
        let tokenStore = InMemoryAuthTokenStoreTestsDouble()
        let store = AuthStore(apiClient: apiClient, tokenStore: tokenStore)
        apiClient.emailOTPRegisterResult = .success(
            RemoteAuthResponse(
                user: .init(id: "user-otp", email: "otp@example.com"),
                workspace: .init(id: "workspace-otp", name: "椰子面试"),
                session: .init(
                    token: "otp-token",
                    refreshToken: "otp-refresh",
                    expiresAt: Date(timeIntervalSince1970: 1_000)
                )
            )
        )

        let didRegister = await store.registerWithEmailOTP(email: "otp@example.com", token: "123456")

        #expect(didRegister == true)
        #expect(store.phase == .needsPasswordSetup)
        #expect(store.currentUser == nil)
        #expect(tokenStore.sessionToken == "otp-token")
        #expect(tokenStore.refreshToken == "otp-refresh")
    }

    @MainActor
    @Test
    func skipPasswordSetupAuthenticatesStoreWithPendingRegistration() async {
        let apiClient = StubAuthClient()
        let tokenStore = InMemoryAuthTokenStoreTestsDouble()
        let store = AuthStore(apiClient: apiClient, tokenStore: tokenStore)
        apiClient.emailOTPRegisterResult = .success(
            RemoteAuthResponse(
                user: .init(id: "user-otp", email: "otp@example.com"),
                workspace: .init(id: "workspace-otp", name: "椰子面试"),
                session: .init(
                    token: "otp-token",
                    refreshToken: "otp-refresh",
                    expiresAt: Date(timeIntervalSince1970: 1_000)
                )
            )
        )

        _ = await store.registerWithEmailOTP(email: "otp@example.com", token: "123456")
        let didSkip = await store.skipPasswordSetup()

        #expect(didSkip == true)
        #expect(store.phase == .authenticated)
        #expect(store.currentUser?.email == "otp@example.com")
        #expect(store.currentWorkspace?.id == "workspace-otp")
    }

    @MainActor
    @Test
    func completePasswordSetupAuthenticatesStore() async {
        let apiClient = StubAuthClient()
        let tokenStore = InMemoryAuthTokenStoreTestsDouble()
        let store = AuthStore(apiClient: apiClient, tokenStore: tokenStore)
        apiClient.emailOTPRegisterResult = .success(
            RemoteAuthResponse(
                user: .init(id: "user-otp", email: "otp@example.com"),
                workspace: .init(id: "workspace-otp", name: "椰子面试"),
                session: .init(
                    token: "otp-token",
                    refreshToken: "otp-refresh",
                    expiresAt: Date(timeIntervalSince1970: 1_000)
                )
            )
        )

        _ = await store.registerWithEmailOTP(email: "otp@example.com", token: "123456")
        let didComplete = await store.completePasswordSetup(password: "password-123")

        #expect(didComplete == true)
        #expect(apiClient.updatedPassword == "password-123")
        #expect(store.phase == .authenticated)
        #expect(store.currentUser?.email == "otp@example.com")
    }

    @MainActor
    @Test
    func resendVerificationEmailKeepsAwaitingState() async {
        let apiClient = StubAuthClient()
        let tokenStore = InMemoryAuthTokenStoreTestsDouble()
        let store = AuthStore(apiClient: apiClient, tokenStore: tokenStore)
        store.phase = .awaitingEmailVerification
        store.pendingVerificationEmail = "verify@example.com"

        let didSubmit = await store.resendVerificationEmail(email: "verify@example.com")

        #expect(didSubmit == true)
        #expect(apiClient.requestedVerificationEmail == "verify@example.com")
        #expect(store.phase == .awaitingEmailVerification)
        #expect(store.lastInfoMessage == "验证邮件已重新发送，请检查邮箱。")
    }

    @MainActor
    @Test
    func authCallbackPersistsTokensAndAuthenticatesStore() async {
        let apiClient = StubAuthClient()
        let tokenStore = InMemoryAuthTokenStoreTestsDouble()
        let store = AuthStore(apiClient: apiClient, tokenStore: tokenStore)
        store.phase = .awaitingEmailVerification
        store.pendingVerificationEmail = "verify@example.com"
        apiClient.sessionResult = .success(
            RemoteAuthSessionState(
                user: .init(id: "user-1", email: "verify@example.com"),
                workspace: .init(id: "workspace-1", name: "椰子面试"),
                session: .init(
                    token: "access-token",
                    refreshToken: "refresh-token",
                    expiresAt: Date(timeIntervalSince1970: 2_000)
                )
            )
        )

        let callbackURL = URL(
            string: "cocointerview://auth/callback#access_token=access-token&refresh_token=refresh-token&type=signup"
        )!

        let didHandle = await store.handleAuthCallback(url: callbackURL)

        #expect(didHandle == true)
        #expect(apiClient.fetchAuthSessionCallCount == 1)
        #expect(tokenStore.sessionToken == "access-token")
        #expect(tokenStore.refreshToken == "refresh-token")
        #expect(store.phase == .authenticated)
        #expect(store.currentUser?.email == "verify@example.com")
        #expect(store.pendingVerificationEmail == nil)
    }

    @MainActor
    @Test
    func authCallbackWithoutTokensIsIgnored() async {
        let apiClient = StubAuthClient()
        let tokenStore = InMemoryAuthTokenStoreTestsDouble()
        let store = AuthStore(apiClient: apiClient, tokenStore: tokenStore)

        let callbackURL = URL(string: "cocointerview://auth/callback?type=signup")!

        let didHandle = await store.handleAuthCallback(url: callbackURL)

        #expect(didHandle == false)
        #expect(apiClient.fetchAuthSessionCallCount == 0)
        #expect(tokenStore.sessionToken == nil)
        #expect(tokenStore.refreshToken == nil)
        #expect(store.phase == .unauthenticated)
    }
}
