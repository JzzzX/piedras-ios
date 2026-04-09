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
    func listMeetingsSendsRequestedWorkspaceHeader() async throws {
        APIClientAuthMockURLProtocol.reset()
        defer { APIClientAuthMockURLProtocol.reset() }

        let suiteName = "piedras.tests.auth.workspace-header.\(UUID().uuidString)"
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
            return (response, Data("[]".utf8))
        }

        _ = try await client.listMeetings(workspaceID: "workspace-project")

        #expect(
            APIClientAuthMockURLProtocol.requests.first?.value(forHTTPHeaderField: "X-Workspace-Id")
                == "workspace-project"
        )
    }

    @MainActor
    @Test
    func listMeetingsRefreshesExpiredSessionAndRetriesOnce() async throws {
        APIClientAuthMockURLProtocol.reset()
        defer { APIClientAuthMockURLProtocol.reset() }

        let suiteName = "piedras.tests.auth.retry.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let settingsStore = SettingsStore(
            defaults: defaults,
            debugDefaultBackendBaseURLString: "https://example.com"
        )
        let tokenStore = UserDefaultsAuthTokenStore(defaults: defaults)
        tokenStore.sessionToken = "expired-session-token"
        tokenStore.refreshToken = "refresh-token-1"

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [APIClientAuthMockURLProtocol.self]
        let client = APIClient(
            settingsStore: settingsStore,
            authTokenStore: tokenStore,
            session: URLSession(configuration: configuration)
        )

        APIClientAuthMockURLProtocol.requestHandler = { request in
            let path = request.url?.path
            switch path {
            case "/api/meetings":
                let requestCount = APIClientAuthMockURLProtocol.requests.filter { $0.url?.path == "/api/meetings" }.count
                let statusCode = requestCount == 1 ? 401 : 200
                let response = try #require(
                    HTTPURLResponse(
                        url: request.url ?? URL(string: "https://example.com/api/meetings")!,
                        statusCode: statusCode,
                        httpVersion: nil,
                        headerFields: ["Content-Type": "application/json"]
                    )
                )
                let payload = statusCode == 401
                    ? #"{"error":"登录态已失效，请重新登录"}"#
                    : "[]"
                return (response, Data(payload.utf8))

            case "/api/auth/refresh":
                let response = try #require(
                    HTTPURLResponse(
                        url: request.url ?? URL(string: "https://example.com/api/auth/refresh")!,
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
                    "token": "fresh-session-token",
                    "refreshToken": "refresh-token-2",
                    "expiresAt": "2026-03-27T10:00:00.000Z"
                  },
                  "requiresEmailVerification": false,
                  "verificationEmail": null
                }
                """
                return (response, Data(payload.utf8))

            default:
                throw URLError(.badServerResponse)
            }
        }

        let meetings = try await client.listMeetings(workspaceID: "workspace-project")

        #expect(meetings.isEmpty)
        #expect(APIClientAuthMockURLProtocol.requests.map { $0.url?.path } == [
            "/api/meetings",
            "/api/auth/refresh",
            "/api/meetings",
        ])
        #expect(
            APIClientAuthMockURLProtocol.requests.last?.value(forHTTPHeaderField: "Authorization")
                == "Bearer fresh-session-token"
        )
        #expect(tokenStore.sessionToken == "fresh-session-token")
        #expect(tokenStore.refreshToken == "refresh-token-2")
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

    @MainActor
    @Test
    func downloadAuthenticatedDataUsesBearerTokenHeader() async throws {
        APIClientAuthMockURLProtocol.reset()
        defer { APIClientAuthMockURLProtocol.reset() }

        let suiteName = "piedras.tests.auth.download.\(UUID().uuidString)"
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
                    headerFields: ["Content-Type": "audio/m4a"]
                )
            )
            return (response, Data("audio-data".utf8))
        }

        let data = try await client.downloadAuthenticatedData(
            fromAbsoluteURLString: "https://example.com/api/meetings/meeting-1/audio"
        )

        #expect(String(decoding: data, as: UTF8.self) == "audio-data")
        #expect(APIClientAuthMockURLProtocol.requests.count == 1)
        #expect(APIClientAuthMockURLProtocol.requests.first?.url?.path == "/api/meetings/meeting-1/audio")
        #expect(
            APIClientAuthMockURLProtocol.requests.first?.value(forHTTPHeaderField: "Authorization")
                == "Bearer session-token"
        )
    }

    @MainActor
    @Test
    func downloadAuthenticatedDataResolvesRelativeFileURLAgainstBackendBaseURL() async throws {
        APIClientAuthMockURLProtocol.reset()
        defer { APIClientAuthMockURLProtocol.reset() }

        let suiteName = "piedras.tests.auth.download-relative.\(UUID().uuidString)"
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
            let url = try #require(request.url)
            let response = try #require(
                HTTPURLResponse(
                    url: url,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/octet-stream"]
                )
            )
            return (response, Data("attachment".utf8))
        }

        let data = try await client.downloadAuthenticatedData(
            fromAbsoluteURLString: "/api/meetings/meeting-1/attachments/attachment-1"
        )

        #expect(String(decoding: data, as: UTF8.self) == "attachment")
        #expect(APIClientAuthMockURLProtocol.requests.count == 1)
        #expect(
            APIClientAuthMockURLProtocol.requests.first?.url?.absoluteString
                == "https://example.com/api/meetings/meeting-1/attachments/attachment-1"
        )
        #expect(
            APIClientAuthMockURLProtocol.requests.first?.value(forHTTPHeaderField: "Authorization")
                == "Bearer session-token"
        )
    }
}
