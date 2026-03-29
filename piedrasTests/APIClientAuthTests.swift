import Foundation
import Testing
@testable import piedras

private final class APIClientAuthMockURLProtocol: URLProtocol {
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?
    static var requests: [URLRequest] = []

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.requestHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        do {
            Self.requests.append(request)
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}

    static func reset() {
        requestHandler = nil
        requests = []
    }
}

@Suite(.serialized)
struct APIClientAuthTests {
    @MainActor
    @Test
    func fetchAuthSessionSendsBearerTokenHeader() async throws {
        APIClientAuthMockURLProtocol.reset()
        defer { APIClientAuthMockURLProtocol.reset() }

        let suiteName = "piedras.tests.auth.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let settingsStore = SettingsStore(
            defaults: defaults,
            debugDefaultBackendBaseURLString: "https://example.com"
        )
        let tokenStore = UserDefaultsAuthTokenStore(defaults: defaults)
        tokenStore.sessionToken = "session-token"

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [APIClientAuthMockURLProtocol.self]
        let client = APIClient(
            settingsStore: settingsStore,
            authTokenStore: tokenStore,
            session: URLSession(configuration: configuration)
        )

        APIClientAuthMockURLProtocol.requestHandler = { request in
            let response = try #require(
                HTTPURLResponse(
                    url: request.url ?? URL(string: "https://example.com")!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                )
            )
            let payload = """
            {
              "user": { "id": "user-1", "email": "test@example.com" },
              "workspace": { "id": "workspace-1", "name": "Piedras" },
              "session": { "expiresAt": "2026-03-27T10:00:00.000Z" }
            }
            """
            return (response, Data(payload.utf8))
        }

        let sessionState = try await client.fetchAuthSession()

        #expect(sessionState.user.email == "test@example.com")
        #expect(APIClientAuthMockURLProtocol.requests.count == 1)
        #expect(
            APIClientAuthMockURLProtocol.requests.first?.value(forHTTPHeaderField: "Authorization")
                == "Bearer session-token"
        )
    }

    @MainActor
    @Test
    func refreshAuthSessionDoesNotReuseBearerTokenHeader() async throws {
        APIClientAuthMockURLProtocol.reset()
        defer { APIClientAuthMockURLProtocol.reset() }

        let suiteName = "piedras.tests.auth.refresh.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let settingsStore = SettingsStore(
            defaults: defaults,
            debugDefaultBackendBaseURLString: "https://example.com"
        )
        let tokenStore = UserDefaultsAuthTokenStore(defaults: defaults)
        tokenStore.sessionToken = "expired-session-token"

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [APIClientAuthMockURLProtocol.self]
        let client = APIClient(
            settingsStore: settingsStore,
            authTokenStore: tokenStore,
            session: URLSession(configuration: configuration)
        )

        APIClientAuthMockURLProtocol.requestHandler = { request in
            let response = try #require(
                HTTPURLResponse(
                    url: request.url ?? URL(string: "https://example.com")!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                )
            )
            let payload = """
            {
              "user": { "id": "user-1", "email": "test@example.com" },
              "workspace": { "id": "workspace-1", "name": "Piedras" },
              "session": {
                "token": "new-session-token",
                "refreshToken": "new-refresh-token",
                "expiresAt": "2026-03-27T10:00:00.000Z"
              },
              "requiresEmailVerification": false,
              "verificationEmail": null
            }
            """
            return (response, Data(payload.utf8))
        }

        _ = try await client.refreshAuthSession(refreshToken: "refresh-token")

        #expect(APIClientAuthMockURLProtocol.requests.count == 1)
        #expect(
            APIClientAuthMockURLProtocol.requests.first?.value(forHTTPHeaderField: "Authorization")
                == nil
        )
    }

    @MainActor
    @Test
    func sendEmailOTPUsesDedicatedEndpointWithoutBearerToken() async throws {
        APIClientAuthMockURLProtocol.reset()
        defer { APIClientAuthMockURLProtocol.reset() }

        let suiteName = "piedras.tests.auth.otp.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let settingsStore = SettingsStore(
            defaults: defaults,
            debugDefaultBackendBaseURLString: "https://example.com"
        )
        let tokenStore = UserDefaultsAuthTokenStore(defaults: defaults)
        tokenStore.sessionToken = "session-token"

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [APIClientAuthMockURLProtocol.self]
        let client = APIClient(
            settingsStore: settingsStore,
            authTokenStore: tokenStore,
            session: URLSession(configuration: configuration)
        )

        APIClientAuthMockURLProtocol.requestHandler = { request in
            let response = try #require(
                HTTPURLResponse(
                    url: request.url ?? URL(string: "https://example.com")!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                )
            )
            return (response, Data("{}".utf8))
        }

        try await client.sendEmailOTP(email: "otp@example.com", intent: .register)

        #expect(APIClientAuthMockURLProtocol.requests.count == 1)
        #expect(APIClientAuthMockURLProtocol.requests.first?.url?.path == "/api/auth/email-otp/send")
        #expect(APIClientAuthMockURLProtocol.requests.first?.value(forHTTPHeaderField: "Authorization") == nil)
    }

    @MainActor
    @Test
    func setPasswordUsesAuthenticatedEndpoint() async throws {
        APIClientAuthMockURLProtocol.reset()
        defer { APIClientAuthMockURLProtocol.reset() }

        let suiteName = "piedras.tests.auth.password-set.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let settingsStore = SettingsStore(
            defaults: defaults,
            debugDefaultBackendBaseURLString: "https://example.com"
        )
        let tokenStore = UserDefaultsAuthTokenStore(defaults: defaults)
        tokenStore.sessionToken = "session-token"

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [APIClientAuthMockURLProtocol.self]
        let client = APIClient(
            settingsStore: settingsStore,
            authTokenStore: tokenStore,
            session: URLSession(configuration: configuration)
        )

        APIClientAuthMockURLProtocol.requestHandler = { request in
            let response = try #require(
                HTTPURLResponse(
                    url: request.url ?? URL(string: "https://example.com")!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                )
            )
            return (response, Data("{}".utf8))
        }

        try await client.setPassword(password: "password-123")

        #expect(APIClientAuthMockURLProtocol.requests.count == 1)
        #expect(APIClientAuthMockURLProtocol.requests.first?.url?.path == "/api/auth/password/set")
        #expect(
            APIClientAuthMockURLProtocol.requests.first?.value(forHTTPHeaderField: "Authorization")
                == "Bearer session-token"
        )
    }
}
