import Foundation
import Observation

enum AuthPhase: Equatable {
    case unauthenticated
    case restoring
    case submitting
    case authenticated
}

@MainActor
@Observable
final class AuthStore {
    private let apiClient: any AuthNetworking
    private let tokenStore: any AuthTokenStoring

    var phase: AuthPhase = .unauthenticated
    var currentUser: RemoteAuthUser?
    var currentWorkspace: RemoteWorkspace?
    var lastErrorMessage: String?
    var logoutBlockedMessage: String?
    var logoutBlockMessageProvider: (() -> String?)?
    var didAuthenticate: ((RemoteAuthUser, RemoteWorkspace) async -> Void)?
    var didUnauthenticate: (() async -> Void)?

    init(apiClient: any AuthNetworking, tokenStore: any AuthTokenStoring) {
        self.apiClient = apiClient
        self.tokenStore = tokenStore
    }

    var isAuthenticated: Bool {
        phase == .authenticated
    }

    func restoreSession() async {
        lastErrorMessage = nil
        logoutBlockedMessage = nil

        guard tokenStore.sessionToken?.nilIfBlank != nil else {
            await clearSession()
            return
        }

        phase = .restoring

        do {
            let sessionState = try await apiClient.fetchAuthSession()
            await applyAuthenticatedSession(
                user: sessionState.user,
                workspace: sessionState.workspace
            )
        } catch {
            lastErrorMessage = error.localizedDescription
            await clearSession()
        }
    }

    @discardableResult
    func login(email: String, password: String) async -> Bool {
        phase = .submitting
        lastErrorMessage = nil
        logoutBlockedMessage = nil

        do {
            let response = try await apiClient.login(email: email, password: password)
            tokenStore.sessionToken = response.session.token
            await applyAuthenticatedSession(
                user: response.user,
                workspace: response.workspace
            )
            return true
        } catch {
            lastErrorMessage = error.localizedDescription
            phase = .unauthenticated
            return false
        }
    }

    @discardableResult
    func register(
        email: String,
        password: String,
        inviteCode: String,
        displayName: String? = nil
    ) async -> Bool {
        phase = .submitting
        lastErrorMessage = nil
        logoutBlockedMessage = nil

        do {
            let response = try await apiClient.register(
                email: email,
                password: password,
                inviteCode: inviteCode,
                displayName: displayName
            )
            tokenStore.sessionToken = response.session.token
            await applyAuthenticatedSession(
                user: response.user,
                workspace: response.workspace
            )
            return true
        } catch {
            lastErrorMessage = error.localizedDescription
            phase = .unauthenticated
            return false
        }
    }

    @discardableResult
    func logout(force: Bool = false) async -> Bool {
        lastErrorMessage = nil

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

    private func applyAuthenticatedSession(
        user: RemoteAuthUser,
        workspace: RemoteWorkspace
    ) async {
        currentUser = user
        currentWorkspace = workspace
        phase = .authenticated
        await didAuthenticate?(user, workspace)
    }

    private func clearSession() async {
        tokenStore.clearSessionToken()
        currentUser = nil
        currentWorkspace = nil
        phase = .unauthenticated
        await didUnauthenticate?()
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
