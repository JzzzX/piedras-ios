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
    let refreshToken: String?
    let expiresAt: Date

    init(token: String? = nil, refreshToken: String? = nil, expiresAt: Date) {
        self.token = token
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
    }
}

struct RemoteAuthResponse: Decodable, Equatable {
    let user: RemoteAuthUser
    let workspace: RemoteWorkspace
    let session: RemoteAuthSession
    let requiresEmailVerification: Bool
    let verificationEmail: String?

    init(
        user: RemoteAuthUser,
        workspace: RemoteWorkspace,
        session: RemoteAuthSession,
        requiresEmailVerification: Bool = false,
        verificationEmail: String? = nil
    ) {
        self.user = user
        self.workspace = workspace
        self.session = session
        self.requiresEmailVerification = requiresEmailVerification
        self.verificationEmail = verificationEmail
    }
}

struct RemoteAuthSessionState: Decodable, Equatable {
    let user: RemoteAuthUser
    let workspace: RemoteWorkspace
    let session: RemoteAuthSession
}

enum EmailOTPIntent: String, Codable, Equatable {
    case login
    case register
}

@MainActor
protocol AuthNetworking: AnyObject {
    func login(email: String, password: String) async throws -> RemoteAuthResponse

    func register(
        email: String,
        password: String,
        displayName: String?
    ) async throws -> RemoteAuthResponse

    func sendEmailOTP(email: String, intent: EmailOTPIntent) async throws

    func loginWithEmailOTP(email: String, token: String) async throws -> RemoteAuthResponse

    func registerWithEmailOTP(email: String, token: String) async throws -> RemoteAuthResponse

    func setPassword(password: String) async throws

    func refreshAuthSession(refreshToken: String) async throws -> RemoteAuthResponse

    func fetchAuthSession() async throws -> RemoteAuthSessionState

    func logout() async throws

    func requestPasswordReset(email: String) async throws

    func resendVerificationEmail(email: String) async throws
}
