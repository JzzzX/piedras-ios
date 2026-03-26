import Foundation

struct RemoteAuthUser: Decodable, Equatable {
    let id: String
    let email: String
    let displayName: String?

    init(id: String, email: String, displayName: String? = nil) {
        self.id = id
        self.email = email
        self.displayName = displayName
    }
}

struct RemoteAuthSession: Decodable, Equatable {
    let token: String?
    let expiresAt: Date

    init(token: String? = nil, expiresAt: Date) {
        self.token = token
        self.expiresAt = expiresAt
    }
}

struct RemoteAuthResponse: Decodable, Equatable {
    let user: RemoteAuthUser
    let workspace: RemoteWorkspace
    let session: RemoteAuthSession
}

struct RemoteAuthSessionState: Decodable, Equatable {
    let user: RemoteAuthUser
    let workspace: RemoteWorkspace
    let session: RemoteAuthSession
}

@MainActor
protocol AuthNetworking: AnyObject {
    func login(email: String, password: String) async throws -> RemoteAuthResponse

    func register(
        email: String,
        password: String,
        inviteCode: String,
        displayName: String?
    ) async throws -> RemoteAuthResponse

    func fetchAuthSession() async throws -> RemoteAuthSessionState

    func logout() async throws
}
