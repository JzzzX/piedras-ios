import Foundation
import Testing
@testable import piedras

@MainActor
private final class StubAuthClient: AuthNetworking {
    var loginResult: Result<RemoteAuthResponse, Error> = .failure(APIClientError.invalidResponse)
    var registerResult: Result<RemoteAuthResponse, Error> = .failure(APIClientError.invalidResponse)
    var sessionResult: Result<RemoteAuthSessionState, Error> = .failure(APIClientError.invalidResponse)
    var logoutCallCount = 0

    func login(email: String, password: String) async throws -> RemoteAuthResponse {
        try loginResult.get()
    }

    func register(
        email: String,
        password: String,
        inviteCode: String,
        displayName: String?
    ) async throws -> RemoteAuthResponse {
        try registerResult.get()
    }

    func fetchAuthSession() async throws -> RemoteAuthSessionState {
        try sessionResult.get()
    }

    func logout() async throws {
        logoutCallCount += 1
    }
}

@MainActor
private final class InMemoryAuthTokenStoreTestsDouble: AuthTokenStoring {
    var sessionToken: String?

    init(sessionToken: String? = nil) {
        self.sessionToken = sessionToken
    }

    func clearSessionToken() {
        sessionToken = nil
    }
}

struct AuthStoreTests {
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
                workspace: .init(id: "workspace-1", name: "Piedras"),
                session: .init(token: "session-token", expiresAt: Date(timeIntervalSince1970: 1_000))
            )
        )

        let didLogin = await store.login(email: "test@example.com", password: "password-123")

        #expect(didLogin == true)
        #expect(store.phase == .authenticated)
        #expect(store.currentUser?.email == "test@example.com")
        #expect(tokenStore.sessionToken == "session-token")
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
                workspace: .init(id: "workspace-1", name: "Piedras"),
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
        let tokenStore = InMemoryAuthTokenStoreTestsDouble(sessionToken: "expired-token")
        let store = AuthStore(apiClient: apiClient, tokenStore: tokenStore)
        apiClient.sessionResult = .failure(APIClientError.requestFailed("expired"))

        await store.restoreSession()

        #expect(store.phase == .unauthenticated)
        #expect(store.currentUser == nil)
        #expect(tokenStore.sessionToken == nil)
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
                workspace: .init(id: "workspace-1", name: "Piedras"),
                session: .init(token: "session-token", expiresAt: Date(timeIntervalSince1970: 1_000))
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
        store.currentWorkspace = .init(id: "workspace-1", name: "Piedras")
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
        store.currentWorkspace = .init(id: "workspace-1", name: "Piedras")
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
        store.currentWorkspace = .init(id: "workspace-1", name: "Piedras")
        store.phase = .authenticated
        store.logoutBlockMessageProvider = { "还有未同步数据" }

        let didLogout = await store.logout(force: true)

        #expect(didLogout == true)
        #expect(store.phase == .unauthenticated)
        #expect(store.currentUser == nil)
        #expect(tokenStore.sessionToken == nil)
        #expect(apiClient.logoutCallCount == 1)
    }
}
