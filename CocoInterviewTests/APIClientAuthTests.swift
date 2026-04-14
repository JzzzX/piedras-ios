import Foundation
import Testing
@testable import CocoInterview

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
    func fetchWechatAuthURLUsesDedicatedEndpointWithoutBearerToken() async throws {
        APIClientAuthMockURLProtocol.reset()
        defer { APIClientAuthMockURLProtocol.reset() }

        let (client, _, tokenStore) = makeClient()
        tokenStore.sessionToken = "session-token"

        APIClientAuthMockURLProtocol.requestHandler = { request in
            try jsonResponse(
                request,
                """
                {
                  "success": true,
                  "data": {
                    "authUrl": "https://open.weixin.qq.com/connect/oauth2/authorize?state=test-state"
                  }
                }
                """
            )
        }

        let authURL = try await client.fetchOAuthAuthorizationURL(provider: .wechat)

        #expect(authURL.absoluteString == "https://open.weixin.qq.com/connect/oauth2/authorize?state=test-state")
        #expect(APIClientAuthMockURLProtocol.requests.count == 1)
        #expect(APIClientAuthMockURLProtocol.requests.first?.url?.path == "/api/v1/auth/wechat/auth-url")
        #expect(APIClientAuthMockURLProtocol.requests.first?.value(forHTTPHeaderField: "Authorization") == nil)
    }

    @MainActor
    @Test
    func completeOAuthCallbackPayloadDecodesWrappedAuthResponseAndBootstrapsWorkspace() async throws {
        APIClientAuthMockURLProtocol.reset()
        defer { APIClientAuthMockURLProtocol.reset() }

        let (client, _, _) = makeClient()

        APIClientAuthMockURLProtocol.requestHandler = { request in
            switch request.url?.path {
            case "/api/v1/interview/workspaces":
                return try jsonResponse(request, #"[{ "id": "workspace-oauth", "name": "椰子面试 iOS" }]"#)
            default:
                throw URLError(.badServerResponse)
            }
        }

        let payload = Data(
            """
            {
              "success": true,
              "data": {
                "user": {
                  "id": "user-wechat",
                  "email": null,
                  "phone": null,
                  "userMetadata": {
                    "nickname": "微信用户"
                  }
                },
                "accessToken": "wechat-access-token",
                "accessTokenExpiresAt": "2026-04-14T11:00:00.000Z",
                "refreshToken": "wechat-refresh-token",
                "refreshTokenExpiresAt": "2026-05-14T10:00:00.000Z",
                "session": {
                  "id": "session-1",
                  "jti": "session-1",
                  "createdAt": "2026-04-14T10:00:00.000Z",
                  "expiresAt": "2026-05-14T10:00:00.000Z",
                  "lastActivityAt": "2026-04-14T10:00:00.000Z"
                }
              }
            }
            """.utf8
        )

        let response = try await client.completeOAuthCallbackPayload(payload)

        #expect(response.user.id == "user-wechat")
        #expect(response.user.displayName == "微信用户")
        #expect(response.workspace.id == "workspace-oauth")
        #expect(response.session.token == "wechat-access-token")
        #expect(response.session.refreshToken == "wechat-refresh-token")
        #expect(APIClientAuthMockURLProtocol.requests.map(\.url?.path) == [
            "/api/v1/interview/workspaces",
        ])
        #expect(
            APIClientAuthMockURLProtocol.requests.first?.value(forHTTPHeaderField: "Authorization")
                == "Bearer wechat-access-token"
        )
    }

    @MainActor
    @Test
    func loginUsesUnifiedAuthEndpointAndBootstrapsWorkspace() async throws {
        APIClientAuthMockURLProtocol.reset()
        defer { APIClientAuthMockURLProtocol.reset() }

        let (client, _, _) = makeClient()

        APIClientAuthMockURLProtocol.requestHandler = { request in
            let path = request.url?.path
            switch path {
            case "/api/v1/auth":
                return try jsonResponse(
                    request,
                    """
                    {
                      "success": true,
                      "data": {
                        "user": {
                          "id": "user-1",
                          "email": "test@example.com",
                          "phone": null,
                          "emailVerified": true,
                          "phoneVerified": false,
                          "role": "user",
                          "isActive": true,
                          "isAnonymous": false,
                          "createdAt": "2026-04-14T10:00:00.000Z",
                          "updatedAt": "2026-04-14T10:00:00.000Z"
                        },
                        "accessToken": "new-session-token",
                        "accessTokenExpiresAt": "2026-04-14T11:00:00.000Z",
                        "refreshToken": "new-refresh-token",
                        "refreshTokenExpiresAt": "2026-05-14T10:00:00.000Z",
                        "session": {
                          "id": "session-1",
                          "jti": "session-1",
                          "createdAt": "2026-04-14T10:00:00.000Z",
                          "expiresAt": "2026-05-14T10:00:00.000Z",
                          "lastActivityAt": "2026-04-14T10:00:00.000Z"
                        }
                      }
                    }
                    """
                )
            case "/api/v1/interview/workspaces":
                return try jsonResponse(request, #"[{ "id": "workspace-1", "name": "椰子面试 iOS" }]"#)
            default:
                throw URLError(.badServerResponse)
            }
        }

        let response = try await client.login(email: "test@example.com", password: "password-123")

        #expect(response.user.email == "test@example.com")
        #expect(response.workspace.id == "workspace-1")
        #expect(response.session.token == "new-session-token")
        #expect(response.session.refreshToken == "new-refresh-token")
        #expect(APIClientAuthMockURLProtocol.requests.map(\.url?.path) == [
            "/api/v1/auth",
            "/api/v1/interview/workspaces",
        ])
        #expect(APIClientAuthMockURLProtocol.requests.first?.value(forHTTPHeaderField: "Authorization") == nil)
    }

    @MainActor
    @Test
    func fetchAuthSessionUsesUserServiceAndCreatesWorkspaceWhenNeeded() async throws {
        APIClientAuthMockURLProtocol.reset()
        defer { APIClientAuthMockURLProtocol.reset() }

        let (client, _, tokenStore) = makeClient()
        tokenStore.sessionToken = "session-token"

        APIClientAuthMockURLProtocol.requestHandler = { request in
            let path = request.url?.path
            switch path {
            case "/api/v1/user/users/me":
                return try jsonResponse(
                    request,
                    """
                    {
                      "success": true,
                      "data": {
                        "id": "user-1",
                        "email": "test@example.com",
                        "phone": null,
                        "nickname": "测试用户",
                        "avatar": null,
                        "role": "user",
                        "paymentTier": "free",
                        "createdAt": "2026-04-14T10:00:00.000Z",
                        "updatedAt": "2026-04-14T10:00:00.000Z"
                      }
                    }
                    """
                )
            case "/api/v1/interview/workspaces":
                if request.httpMethod == "GET" {
                    return try jsonResponse(request, "[]")
                }
                return try jsonResponse(request, #"{ "id": "workspace-ios", "name": "椰子面试 iOS" }"#, statusCode: 201)
            default:
                throw URLError(.badServerResponse)
            }
        }

        let sessionState = try await client.fetchAuthSession()

        #expect(sessionState.user.email == "test@example.com")
        #expect(sessionState.user.displayName == "测试用户")
        #expect(sessionState.workspace.id == "workspace-ios")
        #expect(APIClientAuthMockURLProtocol.requests.map(\.url?.path) == [
            "/api/v1/user/users/me",
            "/api/v1/interview/workspaces",
            "/api/v1/interview/workspaces",
        ])
        #expect(
            APIClientAuthMockURLProtocol.requests.allSatisfy {
                $0.value(forHTTPHeaderField: "Authorization") == "Bearer session-token"
            }
        )
    }

    @MainActor
    @Test
    func refreshAuthSessionDoesNotReuseBearerTokenHeader() async throws {
        APIClientAuthMockURLProtocol.reset()
        defer { APIClientAuthMockURLProtocol.reset() }

        let (client, _, tokenStore) = makeClient()
        tokenStore.sessionToken = "expired-session-token"

        APIClientAuthMockURLProtocol.requestHandler = { request in
            let path = request.url?.path
            switch path {
            case "/api/v1/auth/token/refresh":
                return try jsonResponse(
                    request,
                    """
                    {
                      "success": true,
                      "data": {
                        "user": {
                          "id": "user-1",
                          "email": "test@example.com",
                          "phone": null,
                          "emailVerified": true,
                          "phoneVerified": false,
                          "role": "user",
                          "isActive": true,
                          "isAnonymous": false,
                          "createdAt": "2026-04-14T10:00:00.000Z",
                          "updatedAt": "2026-04-14T10:00:00.000Z"
                        },
                        "accessToken": "fresh-session-token",
                        "accessTokenExpiresAt": "2026-04-14T11:00:00.000Z",
                        "refreshToken": "fresh-refresh-token",
                        "refreshTokenExpiresAt": "2026-05-14T10:00:00.000Z",
                        "session": {
                          "id": "session-1",
                          "jti": "session-1",
                          "createdAt": "2026-04-14T10:00:00.000Z",
                          "expiresAt": "2026-05-14T10:00:00.000Z",
                          "lastActivityAt": "2026-04-14T10:00:00.000Z"
                        }
                      }
                    }
                    """
                )
            case "/api/v1/interview/workspaces":
                return try jsonResponse(request, #"[{ "id": "workspace-1", "name": "椰子面试" }]"#)
            default:
                throw URLError(.badServerResponse)
            }
        }

        let response = try await client.refreshAuthSession(refreshToken: "refresh-token")

        #expect(response.workspace.id == "workspace-1")
        #expect(APIClientAuthMockURLProtocol.requests.map(\.url?.path) == [
            "/api/v1/auth/token/refresh",
            "/api/v1/interview/workspaces",
        ])
        #expect(APIClientAuthMockURLProtocol.requests.first?.value(forHTTPHeaderField: "Authorization") == nil)
    }

    @MainActor
    @Test
    func sendEmailOTPUsesDedicatedEndpointWithoutBearerToken() async throws {
        APIClientAuthMockURLProtocol.reset()
        defer { APIClientAuthMockURLProtocol.reset() }

        let (client, _, tokenStore) = makeClient()
        tokenStore.sessionToken = "session-token"

        APIClientAuthMockURLProtocol.requestHandler = { request in
            try jsonResponse(
                request,
                """
                {
                  "success": true,
                  "message": "OTP sent",
                  "data": { "expiresIn": 300 }
                }
                """
            )
        }

        try await client.sendEmailOTP(email: "otp@example.com", intent: .register)

        #expect(APIClientAuthMockURLProtocol.requests.count == 1)
        #expect(APIClientAuthMockURLProtocol.requests.first?.url?.path == "/api/v1/auth/otp/send")
        #expect(APIClientAuthMockURLProtocol.requests.first?.value(forHTTPHeaderField: "Authorization") == nil)
    }

    @MainActor
    @Test
    func listMeetingsSendsRequestedWorkspaceHeader() async throws {
        APIClientAuthMockURLProtocol.reset()
        defer { APIClientAuthMockURLProtocol.reset() }

        let (client, _, tokenStore) = makeClient()
        tokenStore.sessionToken = "session-token"

        APIClientAuthMockURLProtocol.requestHandler = { request in
            try jsonResponse(request, "[]")
        }

        _ = try await client.listMeetings(workspaceID: "workspace-project")

        #expect(
            APIClientAuthMockURLProtocol.requests.first?.value(forHTTPHeaderField: "X-Workspace-Id")
                == "workspace-project"
        )
        #expect(APIClientAuthMockURLProtocol.requests.first?.url?.path == "/api/v1/interview/meetings")
    }

    @MainActor
    @Test
    func listMeetingsRefreshesExpiredSessionAndRetriesOnce() async throws {
        APIClientAuthMockURLProtocol.reset()
        defer { APIClientAuthMockURLProtocol.reset() }

        let (client, _, tokenStore) = makeClient()
        tokenStore.sessionToken = "expired-session-token"
        tokenStore.refreshToken = "refresh-token-1"

        APIClientAuthMockURLProtocol.requestHandler = { request in
            let path = request.url?.path
            switch path {
            case "/api/v1/interview/meetings":
                let requestCount = APIClientAuthMockURLProtocol.requests.filter {
                    $0.url?.path == "/api/v1/interview/meetings"
                }.count
                if requestCount == 1 {
                    return try jsonResponse(
                        request,
                        #"{"error":{"message":"登录态已失效，请重新登录"}}"#,
                        statusCode: 401
                    )
                }
                return try jsonResponse(request, "[]")

            case "/api/v1/auth/token/refresh":
                return try jsonResponse(
                    request,
                    """
                    {
                      "success": true,
                      "data": {
                        "user": {
                          "id": "user-1",
                          "email": "test@example.com",
                          "phone": null,
                          "emailVerified": true,
                          "phoneVerified": false,
                          "role": "user",
                          "isActive": true,
                          "isAnonymous": false,
                          "createdAt": "2026-04-14T10:00:00.000Z",
                          "updatedAt": "2026-04-14T10:00:00.000Z"
                        },
                        "accessToken": "fresh-session-token",
                        "accessTokenExpiresAt": "2026-04-14T11:00:00.000Z",
                        "refreshToken": "refresh-token-2",
                        "refreshTokenExpiresAt": "2026-05-14T10:00:00.000Z",
                        "session": {
                          "id": "session-1",
                          "jti": "session-1",
                          "createdAt": "2026-04-14T10:00:00.000Z",
                          "expiresAt": "2026-05-14T10:00:00.000Z",
                          "lastActivityAt": "2026-04-14T10:00:00.000Z"
                        }
                      }
                    }
                    """
                )

            case "/api/v1/interview/workspaces":
                return try jsonResponse(request, #"[{ "id": "workspace-1", "name": "椰子面试" }]"#)

            default:
                throw URLError(.badServerResponse)
            }
        }

        let meetings = try await client.listMeetings(workspaceID: "workspace-project")

        #expect(meetings.isEmpty)
        #expect(APIClientAuthMockURLProtocol.requests.map(\.url?.path) == [
            "/api/v1/interview/meetings",
            "/api/v1/auth/token/refresh",
            "/api/v1/interview/workspaces",
            "/api/v1/interview/meetings",
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
    func downloadAuthenticatedDataUsesBearerTokenHeader() async throws {
        APIClientAuthMockURLProtocol.reset()
        defer { APIClientAuthMockURLProtocol.reset() }

        let (client, _, tokenStore) = makeClient()
        tokenStore.sessionToken = "session-token"

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
            fromAbsoluteURLString: "https://example.com/api/v1/interview/meetings/meeting-1/audio"
        )

        #expect(String(decoding: data, as: UTF8.self) == "audio-data")
        #expect(APIClientAuthMockURLProtocol.requests.count == 1)
        #expect(APIClientAuthMockURLProtocol.requests.first?.url?.path == "/api/v1/interview/meetings/meeting-1/audio")
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

        let (client, _, tokenStore) = makeClient()
        tokenStore.sessionToken = "session-token"

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
            fromAbsoluteURLString: "/api/v1/interview/meetings/meeting-1/attachments/attachment-1"
        )

        #expect(String(decoding: data, as: UTF8.self) == "attachment")
        #expect(APIClientAuthMockURLProtocol.requests.count == 1)
        #expect(
            APIClientAuthMockURLProtocol.requests.first?.url?.absoluteString
                == "https://example.com/api/v1/interview/meetings/meeting-1/attachments/attachment-1"
        )
        #expect(
            APIClientAuthMockURLProtocol.requests.first?.value(forHTTPHeaderField: "Authorization")
                == "Bearer session-token"
        )
    }

    @MainActor
    private func makeClient() -> (APIClient, SettingsStore, UserDefaultsAuthTokenStore) {
        let suiteName = "cocointerview.tests.auth.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let settingsStore = SettingsStore(
            defaults: defaults,
            debugDefaultBackendBaseURLString: "https://example.com"
        )
        let tokenStore = UserDefaultsAuthTokenStore(defaults: defaults)

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [APIClientAuthMockURLProtocol.self]
        let client = APIClient(
            settingsStore: settingsStore,
            authTokenStore: tokenStore,
            session: URLSession(configuration: configuration)
        )

        return (client, settingsStore, tokenStore)
    }

    private func jsonResponse(
        _ request: URLRequest,
        _ payload: String,
        statusCode: Int = 200
    ) throws -> (HTTPURLResponse, Data) {
        let response = try #require(
            HTTPURLResponse(
                url: request.url ?? URL(string: "https://example.com")!,
                statusCode: statusCode,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )
        )
        return (response, Data(payload.utf8))
    }
}
