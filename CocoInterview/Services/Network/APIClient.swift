import Foundation

private struct APIErrorDetailPayload: Decodable {
    let code: String?
    let message: String?
    let details: String?
}

private struct APIErrorPayload: Decodable {
    let error: String?
    let errorDetail: APIErrorDetailPayload?
    let message: String?
    let requestId: String?
    let route: String?

    enum CodingKeys: String, CodingKey {
        case error
        case message
        case requestId
        case route
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        message = try container.decodeIfPresent(String.self, forKey: .message)
        requestId = try container.decodeIfPresent(String.self, forKey: .requestId)
        route = try container.decodeIfPresent(String.self, forKey: .route)

        if let error = try? container.decodeIfPresent(String.self, forKey: .error) {
            self.error = error
            errorDetail = nil
        } else {
            error = nil
            errorDetail = try container.decodeIfPresent(APIErrorDetailPayload.self, forKey: .error)
        }
    }
}

private struct MeetingTitleRequestPayload: Encodable {
    let transcript: String
    let durationSeconds: Int
    let meetingDate: String
    let promptOptions: PromptOptions?
}

private struct AuthUnifiedRequestPayload: Encodable {
    let email: String
    let password: String?
    let otp: String?
    let userMetadata: [String: String]?
}

private struct AuthUserMetadataPayload: Decodable {
    let nickname: String?
    let displayName: String?
}

private struct AuthUserPayload: Decodable {
    let id: String
    let email: String?
    let phone: String?
    let userMetadata: AuthUserMetadataPayload?
}

private struct AuthSessionPayload: Decodable {
    let id: String?
    let jti: String?
    let createdAt: Date?
    let expiresAt: Date?
    let lastActivityAt: Date?
}

private struct AuthResponsePayload: Decodable {
    let user: AuthUserPayload?
    let accessToken: String?
    let accessTokenExpiresAt: Date?
    let refreshToken: String?
    let refreshTokenExpiresAt: Date?
    let session: AuthSessionPayload?
    let requiresOtp: Bool?
    let message: String?
    let expiresIn: Int?
}

private struct UserProfilePayload: Decodable {
    let id: String
    let email: String?
    let phone: String?
    let nickname: String?
    let avatar: String?
    let role: String?
    let paymentTier: String?
    let createdAt: Date?
    let updatedAt: Date?
}

private struct WrappedSuccessPayload<DataPayload: Decodable>: Decodable {
    let success: Bool
    let data: DataPayload?
    let message: String?
}

private struct AuthEmailOTPRequestPayload: Encodable {
    let email: String
    let type: String
}

private struct AuthOTPResponsePayload: Decodable {
    let expiresIn: Int?
}

private struct OAuthAuthorizationURLPayload: Decodable {
    let authUrl: String
}

private struct AuthRefreshRequestPayload: Encodable {
    let refreshToken: String
}

private struct ServiceHealthPayload: Decodable {
    let status: String
    let timestamp: Date?
}

private struct RefreshedAuthState {
    let sessionToken: String
    let refreshToken: String?
}

enum APIClientError: LocalizedError {
    case missingBaseURL
    case invalidResponse
    case requestFailed(String)
    case unreadableFile

    var errorDescription: String? {
        switch self {
        case .missingBaseURL:
            return "服务地址不可用。"
        case .invalidResponse:
            return "后端返回了无法识别的响应。"
        case let .requestFailed(message):
            return message
        case .unreadableFile:
            return "本地音频文件读取失败，无法上传。"
        }
    }
}

@MainActor
final class APIClient: AuthNetworking {
    private static let requestIDHeader = "X-Request-Id"
    private static let workspaceIDHeader = "X-Workspace-Id"
    private static let defaultRequestTimeout: TimeInterval = 30
    private static let aiRequestTimeout: TimeInterval = 45
    private static let aiRequestRetryCount = 1
    private let settingsStore: SettingsStore
    private let authTokenStore: any AuthTokenStoring
    private let session: URLSession
    private let encoder = JSONEncoder()
    private let decoder: JSONDecoder
    private var authRefreshTask: Task<RefreshedAuthState, Error>?

    init(
        settingsStore: SettingsStore,
        authTokenStore: (any AuthTokenStoring)? = nil,
        session: URLSession = .shared
    ) {
        self.settingsStore = settingsStore
        self.authTokenStore = authTokenStore ?? KeychainAuthTokenStore()
        self.session = session
        self.decoder = Self.makeJSONDecoder()
    }

    var baseURL: URL? {
        settingsStore.backendBaseURL
    }

    func fetchBackendHealth() async throws -> RemoteBackendHealth {
        let interview = try await sendJSONRequest(
            path: "/api/v1/interview/health",
            method: "GET",
            responseType: ServiceHealthPayload.self
        )
        let ai = try await sendJSONRequest(
            path: "/api/v1/ai/health",
            method: "GET",
            responseType: ServiceHealthPayload.self
        )
        let checkedAt = ai.timestamp ?? interview.timestamp
        return RemoteBackendHealth(
            ok: interview.status == "ok" && ai.status == "ok",
            database: nil,
            asr: makeASRStatus(from: ai),
            llm: makeLLMStatus(from: ai),
            audioFinalization: nil,
            noteAttachments: nil,
            startupBootstrap: nil,
            checkedAt: checkedAt
        )
    }

    func fetchBackendWarmup() async throws -> RemoteBackendHealth {
        try await fetchBackendHealth()
    }

    func fetchASRStatus() async throws -> RemoteASRStatus {
        let health = try await sendJSONRequest(
            path: "/api/v1/ai/health",
            method: "GET",
            responseType: ServiceHealthPayload.self
        )
        return makeASRStatus(from: health)
    }

    func fetchLLMStatus() async throws -> RemoteLLMStatus {
        let health = try await sendJSONRequest(
            path: "/api/v1/ai/health",
            method: "GET",
            responseType: ServiceHealthPayload.self
        )
        return makeLLMStatus(from: health)
    }

    func login(email: String, password: String) async throws -> RemoteAuthResponse {
        try await performUnifiedAuth(
            AuthUnifiedRequestPayload(
                email: email,
                password: password,
                otp: nil,
                userMetadata: nil
            )
        )
    }

    func register(
        email: String,
        password: String,
        displayName: String?
    ) async throws -> RemoteAuthResponse {
        try await performUnifiedAuth(
            AuthUnifiedRequestPayload(
                email: email,
                password: password,
                otp: nil,
                userMetadata: displayName?.nilIfBlank.map { ["displayName": $0] }
            )
        )
    }

    func sendEmailOTP(email: String, intent: EmailOTPIntent) async throws {
        let _: AuthOTPResponsePayload = try await sendWrappedJSONRequest(
            path: "/api/v1/auth/otp/send",
            method: "POST",
            includeAuthorization: false,
            body: AuthEmailOTPRequestPayload(
                email: email,
                type: intent == .login ? "login" : "register"
            )
        )
    }

    func loginWithEmailOTP(email: String, token: String) async throws -> RemoteAuthResponse {
        try await performUnifiedAuth(
            AuthUnifiedRequestPayload(
                email: email,
                password: nil,
                otp: token,
                userMetadata: nil
            )
        )
    }

    func registerWithEmailOTP(email: String, token: String) async throws -> RemoteAuthResponse {
        try await performUnifiedAuth(
            AuthUnifiedRequestPayload(
                email: email,
                password: nil,
                otp: token,
                userMetadata: nil
            )
        )
    }

    func fetchOAuthAuthorizationURL(provider: OAuthProvider) async throws -> URL {
        let payload: OAuthAuthorizationURLPayload = try await sendWrappedJSONRequest(
            path: "/api/v1/auth/\(provider.rawValue)/auth-url",
            method: "GET",
            includeAuthorization: false,
            responseType: OAuthAuthorizationURLPayload.self
        )

        guard let url = URL(string: payload.authUrl) else {
            throw APIClientError.invalidResponse
        }

        return url
    }

    func completeOAuthCallbackPayload(_ payload: Data) async throws -> RemoteAuthResponse {
        if let envelope = try? decoder.decode(WrappedSuccessPayload<AuthResponsePayload>.self, from: payload) {
            guard envelope.success else {
                throw APIClientError.requestFailed(
                    envelope.message?.nilIfBlank ?? "第三方登录失败，请稍后重试。"
                )
            }

            guard let response = envelope.data else {
                throw APIClientError.invalidResponse
            }

            return try await mapAuthResponse(
                response,
                accessTokenOverride: response.accessToken?.nilIfBlank
            )
        }

        throw APIClientError.requestFailed(
            Self.buildErrorMessage(from: payload, fallback: "第三方登录失败，请稍后重试。")
        )
    }

    func setPassword(password: String) async throws {
        throw APIClientError.requestFailed(
            "椰子体系当前未开放应用内补设密码，请改用邮箱验证码或联系管理员。"
        )
    }

    func refreshAuthSession(refreshToken: String) async throws -> RemoteAuthResponse {
        let payload: AuthResponsePayload = try await sendWrappedJSONRequest(
            path: "/api/v1/auth/token/refresh",
            method: "POST",
            includeAuthorization: false,
            body: AuthRefreshRequestPayload(refreshToken: refreshToken)
        )
        return try await mapAuthResponse(payload, accessTokenOverride: payload.accessToken?.nilIfBlank)
    }

    func fetchAuthSession() async throws -> RemoteAuthSessionState {
        guard let sessionToken = authTokenStore.sessionToken?.nilIfBlank else {
            throw APIClientError.requestFailed("登录态已失效，请重新登录。")
        }

        let profile: UserProfilePayload = try await sendWrappedJSONRequest(
            path: "/api/v1/user/users/me",
            method: "GET",
            responseType: UserProfilePayload.self
        )

        let workspace = try await ensureWorkspace(accessTokenOverride: sessionToken)
        let session = RemoteAuthSession(
            token: sessionToken,
            refreshToken: authTokenStore.refreshToken?.nilIfBlank,
            expiresAt: Self.jwtExpirationDate(from: sessionToken) ?? .now.addingTimeInterval(3600)
        )
        return RemoteAuthSessionState(
            user: mapUserProfile(profile),
            workspace: workspace,
            session: session
        )
    }

    func logout() async throws {
        var request = try makeRequest(path: "/api/v1/auth/logout", method: "POST")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data("{}".utf8)
        let (data, response) = try await performDataRequest(request)
        try validate(response: response, data: data, fallback: "退出登录失败。")
    }

    func requestPasswordReset(email: String) async throws {
        throw APIClientError.requestFailed(
            "椰子体系当前未开放应用内密码重置，请改用邮箱验证码登录。"
        )
    }

    func resendVerificationEmail(email: String) async throws {
        throw APIClientError.requestFailed(
            "椰子体系当前未开放邮箱验证补发，请改用邮箱验证码登录。"
        )
    }

    func createASRSession(
        sampleRate: Int,
        channels: Int,
        workspaceID: String?,
        meetingID: String? = nil
    ) async throws -> RemoteASRSessionResponse {
        guard let sessionToken = authTokenStore.sessionToken?.nilIfBlank else {
            throw APIClientError.requestFailed("登录态已失效，请重新登录。")
        }

        guard let wsURL = makeASRWebSocketURL(token: sessionToken, sampleRate: sampleRate) else {
            throw APIClientError.missingBaseURL
        }

        return RemoteASRSessionResponse(
            session: RemoteASRSession(
                wsUrl: wsURL.absoluteString,
                token: nil,
                tokenExpireTime: nil,
                appKey: nil,
                vocabularyId: nil,
                sampleRate: sampleRate,
                channels: channels,
                codec: "pcm",
                packetDurationMs: 200
            ),
            error: nil
        )
    }

    func listWorkspaces() async throws -> [RemoteWorkspace] {
        try await sendJSONRequest(
            path: "/api/v1/interview/workspaces",
            method: "GET",
            responseType: [RemoteWorkspace].self
        )
    }

    func createWorkspace(_ payload: WorkspaceCreatePayload) async throws -> RemoteWorkspace {
        try await sendJSONRequest(path: "/api/v1/interview/workspaces", method: "POST", body: payload)
    }

    func listCollections() async throws -> [RemoteCollection] {
        try await sendJSONRequest(
            path: "/api/v1/interview/collections",
            method: "GET",
            responseType: [RemoteCollection].self
        )
    }

    func createCollection(_ payload: CollectionCreatePayload) async throws -> RemoteCollection {
        try await sendJSONRequest(path: "/api/v1/interview/collections", method: "POST", body: payload)
    }

    func deleteCollection(id: String) async throws {
        let request = try makeRequest(path: "/api/v1/interview/collections/\(id)", method: "DELETE")
        let (data, response) = try await performDataRequest(request)
        try validate(response: response, data: data, fallback: "删除文件夹失败。")
    }

    func listMeetings(workspaceID: String) async throws -> [RemoteMeetingListItem] {
        try await sendJSONRequest(
            path: "/api/v1/interview/meetings",
            method: "GET",
            queryItems: [URLQueryItem(name: "workspaceId", value: workspaceID)],
            extraHeaders: workspaceHeader(workspaceID),
            responseType: [RemoteMeetingListItem].self
        )
    }

    func getMeeting(id: String, workspaceID: String? = nil) async throws -> RemoteMeetingDetail {
        try await sendJSONRequest(
            path: "/api/v1/interview/meetings/\(id)",
            method: "GET",
            extraHeaders: workspaceHeader(workspaceID),
            responseType: RemoteMeetingDetail.self
        )
    }

    func updateMeetingAudioCloudSyncEnabled(
        meetingID: String,
        enabled: Bool,
        workspaceID: String? = nil
    ) async throws -> RemoteMeetingDetail {
        try await sendJSONRequest(
            path: "/api/v1/interview/meetings/\(meetingID)",
            method: "PUT",
            extraHeaders: workspaceHeader(workspaceID),
            body: ["audioCloudSyncEnabled": enabled]
        )
    }

    func upsertMeeting(
        _ payload: MeetingUpsertPayload,
        workspaceID: String? = nil
    ) async throws -> RemoteMeetingDetail {
        try await sendJSONRequest(
            path: "/api/v1/interview/meetings",
            method: "POST",
            extraHeaders: workspaceHeader(workspaceID),
            body: payload
        )
    }

    func deleteMeeting(id: String, workspaceID: String? = nil) async throws {
        let request = try makeRequest(
            path: "/api/v1/interview/meetings/\(id)",
            method: "DELETE",
            extraHeaders: workspaceHeader(workspaceID)
        )
        let (data, response) = try await performDataRequest(request)
        try validate(response: response, data: data, fallback: "删除会议失败。")
    }

    func uploadAudio(
        meetingID: String,
        fileURL: URL,
        duration: Int,
        mimeType: String,
        workspaceID: String? = nil,
        requestTranscriptFinalization: Bool = false
    ) async throws -> RemoteAudioUploadResponse {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw APIClientError.unreadableFile
        }

        var request = try makeRequest(
            path: "/api/meetings/\(meetingID)/audio",
            method: "PUT",
            queryItems: requestTranscriptFinalization
                ? [URLQueryItem(name: "finalizeTranscript", value: "true")]
                : [],
            extraHeaders: workspaceHeader(workspaceID)
        )
        request.timeoutInterval = 15 * 60
        request.setValue(mimeType, forHTTPHeaderField: "Content-Type")
        request.setValue(String(max(duration, 0)), forHTTPHeaderField: "X-Audio-Duration")

        let (data, response) = try await performUploadRequest(request, fromFile: fileURL)
        try validate(response: response, data: data)
        return try decoder.decode(RemoteAudioUploadResponse.self, from: data)
    }

    func deleteRemoteAudio(meetingID: String) async throws {
        let request = try makeRequest(path: "/api/meetings/\(meetingID)/audio", method: "DELETE")
        let (data, response) = try await performDataRequest(request)
        try validate(response: response, data: data, fallback: "删除云端音频失败。")
    }

    func uploadNoteAttachment(
        meetingID: String,
        fileURL: URL,
        mimeType: String,
        workspaceID: String? = nil,
        extractedText: String
    ) async throws -> RemoteNoteAttachmentUploadResponse {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw APIClientError.unreadableFile
        }

        let boundary = "Boundary-\(UUID().uuidString)"
        var request = try makeRequest(
            path: "/api/meetings/\(meetingID)/attachments",
            method: "POST",
            extraHeaders: workspaceHeader(workspaceID)
        )
        request.timeoutInterval = 5 * 60
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        let fileData = try Data(contentsOf: fileURL)
        let body = try Self.makeMultipartBody(
            boundary: boundary,
            fileFieldName: "file",
            fileName: fileURL.lastPathComponent,
            mimeType: mimeType,
            fileData: fileData,
            textFields: [
                "extractedText": extractedText,
            ]
        )

        let (data, response) = try await performUploadRequest(request, from: body)
        try validate(response: response, data: data)
        return try decoder.decode(RemoteNoteAttachmentUploadResponse.self, from: data)
    }

    func deleteNoteAttachment(
        meetingID: String,
        attachmentID: String,
        workspaceID: String? = nil
    ) async throws {
        let request = try makeRequest(
            path: "/api/meetings/\(meetingID)/attachments/\(attachmentID)",
            method: "DELETE",
            extraHeaders: workspaceHeader(workspaceID)
        )
        let (data, response) = try await performDataRequest(request)
        try validate(response: response, data: data, fallback: "删除资料区图片失败。")
    }

    func downloadAuthenticatedData(fromAbsoluteURLString urlString: String) async throws -> Data {
        let resolvedURLString = resolveAbsoluteURLString(urlString) ?? urlString
        guard let url = URL(string: resolvedURLString), url.scheme != nil else {
            throw APIClientError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 60
        request.setValue(Self.makeRequestID(), forHTTPHeaderField: Self.requestIDHeader)
        if let sessionToken = authTokenStore.sessionToken?.nilIfBlank {
            request.setValue("Bearer \(sessionToken)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await performDataRequest(request)
        try validate(response: response, data: data, fallback: "下载文件失败。")
        return data
    }

    func fetchMeetingProcessingStatus(
        meetingID: String,
        workspaceID: String? = nil
    ) async throws -> RemoteMeetingProcessingStatus {
        try await sendJSONRequest(
            path: "/api/v1/interview/meetings/\(meetingID)/processing-status",
            method: "GET",
            extraHeaders: workspaceHeader(workspaceID),
            responseType: RemoteMeetingProcessingStatus.self
        )
    }

    func enhanceNotes(_ payload: EnhanceRequestPayload) async throws -> RemoteEnhanceResponse {
        try await sendRetryableAIJSONRequest(
            path: "/api/v1/interview/enhance",
            method: "POST",
            body: payload,
            fallback: "AI 后处理失败，请稍后重试。"
        )
    }

    func generateMeetingTitle(
        transcript: String,
        durationSeconds: Int,
        meetingDate: Date,
        meetingType: String
    ) async throws -> RemoteMeetingTitleResponse {
        try await sendJSONRequest(
            path: "/api/v1/interview/meetings/title",
            method: "POST",
            body: MeetingTitleRequestPayload(
                transcript: transcript,
                durationSeconds: durationSeconds,
                meetingDate: Self.iso8601WithFractionalSeconds.string(from: meetingDate),
                promptOptions: PromptOptions(
                    meetingType: meetingType,
                    outputStyle: "平衡",
                    includeActionItems: true
                )
            )
        )
    }

    func streamChat(_ payload: ChatRequestPayload) async throws -> AsyncThrowingStream<String, Error> {
        var request = try makeRequest(path: "/api/v1/interview/chat", method: "POST")
        request.timeoutInterval = Self.aiRequestTimeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(payload)

        return makeRetryableAITextStream(request: request, fallback: "会议对话请求失败。")
    }

    func streamGlobalChat(_ payload: GlobalChatRequestPayload) async throws -> AsyncThrowingStream<String, Error> {
        var request = try makeRequest(path: "/api/v1/interview/chat/global", method: "POST")
        request.timeoutInterval = Self.aiRequestTimeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let workspaceID = settingsStore.hiddenWorkspaceID?.nilIfBlank {
            request.setValue(workspaceID, forHTTPHeaderField: Self.workspaceIDHeader)
        }
        request.httpBody = try encoder.encode(payload)

        return makeRetryableAITextStream(request: request, fallback: "全局 AI 请求失败。")
    }

    func resolveAbsoluteURLString(_ path: String?) -> String? {
        guard let path, !path.isEmpty else {
            return nil
        }

        if URL(string: path)?.scheme != nil {
            return path
        }

        guard let baseURL else {
            return path
        }

        return URL(string: path, relativeTo: baseURL)?.absoluteURL.absoluteString ?? path
    }

    private func sendJSONRequest<Response: Decodable>(
        path: String,
        method: String,
        queryItems: [URLQueryItem] = [],
        includeAuthorization: Bool = true,
        extraHeaders: [String: String] = [:],
        responseType: Response.Type
    ) async throws -> Response {
        let request = try makeRequest(
            path: path,
            method: method,
            queryItems: queryItems,
            includeAuthorization: includeAuthorization,
            extraHeaders: extraHeaders
        )
        let (data, response) = try await performDataRequest(request)
        try validate(response: response, data: data)
        return try decoder.decode(responseType, from: data)
    }

    private func sendJSONRequest<Response: Decodable, Body: Encodable>(
        path: String,
        method: String,
        queryItems: [URLQueryItem] = [],
        includeAuthorization: Bool = true,
        extraHeaders: [String: String] = [:],
        body: Body
    ) async throws -> Response {
        var request = try makeRequest(
            path: path,
            method: method,
            queryItems: queryItems,
            includeAuthorization: includeAuthorization,
            extraHeaders: extraHeaders
        )
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(body)

        let (data, response) = try await performDataRequest(request)
        try validate(response: response, data: data)
        return try decoder.decode(Response.self, from: data)
    }

    private func sendWrappedJSONRequest<Response: Decodable>(
        path: String,
        method: String,
        queryItems: [URLQueryItem] = [],
        includeAuthorization: Bool = true,
        extraHeaders: [String: String] = [:],
        responseType: Response.Type
    ) async throws -> Response {
        let request = try makeRequest(
            path: path,
            method: method,
            queryItems: queryItems,
            includeAuthorization: includeAuthorization,
            extraHeaders: extraHeaders
        )
        let (data, response) = try await performDataRequest(request)
        try validate(response: response, data: data)

        let envelope = try decoder.decode(WrappedSuccessPayload<Response>.self, from: data)
        guard envelope.success, let payload = envelope.data else {
            throw APIClientError.invalidResponse
        }
        return payload
    }

    private func sendWrappedJSONRequest<Response: Decodable, Body: Encodable>(
        path: String,
        method: String,
        queryItems: [URLQueryItem] = [],
        includeAuthorization: Bool = true,
        extraHeaders: [String: String] = [:],
        body: Body
    ) async throws -> Response {
        var request = try makeRequest(
            path: path,
            method: method,
            queryItems: queryItems,
            includeAuthorization: includeAuthorization,
            extraHeaders: extraHeaders
        )
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(body)

        let (data, response) = try await performDataRequest(request)
        try validate(response: response, data: data)

        let envelope = try decoder.decode(WrappedSuccessPayload<Response>.self, from: data)
        guard envelope.success, let payload = envelope.data else {
            throw APIClientError.invalidResponse
        }
        return payload
    }

    private func sendRetryableAIJSONRequest<Response: Decodable, Body: Encodable>(
        path: String,
        method: String,
        queryItems: [URLQueryItem] = [],
        includeAuthorization: Bool = true,
        extraHeaders: [String: String] = [:],
        body: Body,
        fallback: String
    ) async throws -> Response {
        var request = try makeRequest(
            path: path,
            method: method,
            queryItems: queryItems,
            includeAuthorization: includeAuthorization,
            extraHeaders: extraHeaders
        )
        request.timeoutInterval = Self.aiRequestTimeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(body)

        let (data, response) = try await performRetryableAIDataRequest(request: request)
        try validate(response: response, data: data, fallback: fallback)
        return try decoder.decode(Response.self, from: data)
    }

    private func makeRequest(
        path: String,
        method: String,
        queryItems: [URLQueryItem] = [],
        includeAuthorization: Bool = true,
        extraHeaders: [String: String] = [:]
    ) throws -> URLRequest {
        guard let baseURL else {
            throw APIClientError.missingBaseURL
        }

        guard let relativeURL = URL(string: path, relativeTo: baseURL) else {
            throw APIClientError.invalidResponse
        }

        guard var components = URLComponents(url: relativeURL, resolvingAgainstBaseURL: true) else {
            throw APIClientError.invalidResponse
        }

        if !queryItems.isEmpty {
            components.queryItems = queryItems
        }

        guard let url = components.url else {
            throw APIClientError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = Self.defaultRequestTimeout
        request.setValue(Self.makeRequestID(), forHTTPHeaderField: Self.requestIDHeader)
        if includeAuthorization,
           let sessionToken = authTokenStore.sessionToken?.nilIfBlank {
            request.setValue("Bearer \(sessionToken)", forHTTPHeaderField: "Authorization")
        }
        for (header, value) in extraHeaders where !value.isEmpty {
            request.setValue(value, forHTTPHeaderField: header)
        }
        return request
    }

    private func workspaceHeader(_ workspaceID: String?) -> [String: String] {
        guard let workspaceID = workspaceID?.nilIfBlank else {
            return [:]
        }
        return [Self.workspaceIDHeader: workspaceID]
    }

    private func performUnifiedAuth(_ payload: AuthUnifiedRequestPayload) async throws -> RemoteAuthResponse {
        let response: AuthResponsePayload = try await sendWrappedJSONRequest(
            path: "/api/v1/auth",
            method: "POST",
            includeAuthorization: false,
            body: payload
        )
        return try await mapAuthResponse(response, accessTokenOverride: response.accessToken?.nilIfBlank)
    }

    private func mapAuthResponse(
        _ payload: AuthResponsePayload,
        accessTokenOverride: String?
    ) async throws -> RemoteAuthResponse {
        if payload.requiresOtp == true {
            let message = payload.message?.nilIfBlank ?? "需要邮箱验证码才能继续。"
            throw APIClientError.requestFailed(message)
        }

        guard let user = payload.user,
              let accessToken = payload.accessToken?.nilIfBlank,
              let accessTokenExpiresAt = payload.accessTokenExpiresAt else {
            throw APIClientError.invalidResponse
        }

        let workspace = try await ensureWorkspace(accessTokenOverride: accessTokenOverride ?? accessToken)
        return RemoteAuthResponse(
            user: mapAuthUser(user),
            workspace: workspace,
            session: RemoteAuthSession(
                token: accessToken,
                refreshToken: payload.refreshToken?.nilIfBlank,
                expiresAt: accessTokenExpiresAt
            )
        )
    }

    private func mapAuthUser(_ payload: AuthUserPayload) -> RemoteAuthUser {
        RemoteAuthUser(
            id: payload.id,
            email: payload.email?.nilIfBlank ?? payload.phone?.nilIfBlank ?? "unknown@coco.local",
            displayName: payload.userMetadata?.displayName?.nilIfBlank
                ?? payload.userMetadata?.nickname?.nilIfBlank
        )
    }

    private func mapUserProfile(_ payload: UserProfilePayload) -> RemoteAuthUser {
        RemoteAuthUser(
            id: payload.id,
            email: payload.email?.nilIfBlank ?? payload.phone?.nilIfBlank ?? "unknown@coco.local",
            displayName: payload.nickname?.nilIfBlank
        )
    }

    private func ensureWorkspace(accessTokenOverride: String?) async throws -> RemoteWorkspace {
        let workspaces: [RemoteWorkspace] = try await sendJSONRequest(
            path: "/api/v1/interview/workspaces",
            method: "GET",
            includeAuthorization: false,
            extraHeaders: authorizationHeader(for: accessTokenOverride),
            responseType: [RemoteWorkspace].self
        )

        if let currentID = settingsStore.hiddenWorkspaceID?.nilIfBlank,
           let matched = workspaces.first(where: { $0.id == currentID }) {
            return matched
        }

        if let existing = workspaces.first(where: { $0.name == "椰子面试 iOS" }) {
            return existing
        }

        if let first = workspaces.first {
            return first
        }

        return try await sendJSONRequest(
            path: "/api/v1/interview/workspaces",
            method: "POST",
            includeAuthorization: false,
            extraHeaders: authorizationHeader(for: accessTokenOverride),
            body: WorkspaceCreatePayload(
                name: "椰子面试 iOS",
                description: "椰子面试 iOS 隐藏工作区",
                icon: "iphone",
                color: "#0f766e",
                workflowMode: "general",
                modeLabel: "iOS"
            )
        )
    }

    private func authorizationHeader(for accessToken: String?) -> [String: String] {
        guard let accessToken = accessToken?.nilIfBlank else {
            return [:]
        }
        return ["Authorization": "Bearer \(accessToken)"]
    }

    private func makeASRStatus(from health: ServiceHealthPayload) -> RemoteASRStatus {
        RemoteASRStatus(
            mode: "coco-ai",
            provider: "coco-ai",
            configured: true,
            reachable: health.status == "ok",
            ready: health.status == "ok",
            missing: [],
            message: health.status == "ok" ? "ASR 服务可用" : "ASR 服务不可用",
            checkedAt: health.timestamp,
            lastError: health.status == "ok" ? nil : "ASR service unavailable"
        )
    }

    private func makeLLMStatus(from health: ServiceHealthPayload) -> RemoteLLMStatus {
        RemoteLLMStatus(
            configured: true,
            reachable: health.status == "ok",
            ready: health.status == "ok",
            provider: "coco-ai",
            model: nil,
            preset: nil,
            message: health.status == "ok" ? "AI 服务可用" : "AI 服务不可用",
            checkedAt: health.timestamp,
            lastError: health.status == "ok" ? nil : "AI service unavailable"
        )
    }

    private func makeASRWebSocketURL(token: String, sampleRate: Int) -> URL? {
        guard let baseURL else {
            return nil
        }

        guard let endpoint = URL(string: "/api/v1/asr/ws", relativeTo: baseURL) else {
            return nil
        }

        guard var components = URLComponents(
            url: endpoint,
            resolvingAgainstBaseURL: true
        ) else {
            return nil
        }

        components.scheme = components.scheme == "https" ? "wss" : "ws"
        components.queryItems = [
            URLQueryItem(name: "token", value: token),
            URLQueryItem(name: "provider", value: "qwen"),
            URLQueryItem(name: "language", value: "zh"),
            URLQueryItem(name: "format", value: "pcm"),
            URLQueryItem(name: "sampleRate", value: String(sampleRate)),
        ]
        return components.url
    }

    private func performDataRequest(
        _ request: URLRequest
    ) async throws -> (Data, URLResponse) {
        try await performRequestWithAuthRefresh(
            request: request,
            operation: { [self] request in
                try await self.session.data(for: request)
            },
            response: { result in result.1 }
        )
    }

    private func performUploadRequest(
        _ request: URLRequest,
        from body: Data
    ) async throws -> (Data, URLResponse) {
        try await performRequestWithAuthRefresh(
            request: request,
            operation: { [self] request in
                try await self.session.upload(for: request, from: body)
            },
            response: { result in result.1 }
        )
    }

    private func performUploadRequest(
        _ request: URLRequest,
        fromFile fileURL: URL
    ) async throws -> (Data, URLResponse) {
        try await performRequestWithAuthRefresh(
            request: request,
            operation: { [self] request in
                try await self.session.upload(for: request, fromFile: fileURL)
            },
            response: { result in result.1 }
        )
    }

    private func performRequestWithAuthRefresh<Result>(
        request: URLRequest,
        operation: @escaping (URLRequest) async throws -> Result,
        response: @escaping (Result) -> URLResponse
    ) async throws -> Result {
        let initialResult = try await operation(request)

        guard shouldAttemptAuthRefresh(for: request, response: response(initialResult)) else {
            return initialResult
        }

        let refreshedState = try await refreshAuthStateForRetry()
        let retriedRequest = requestByUpdatingAuthorization(
            for: request,
            sessionToken: refreshedState.sessionToken
        )
        return try await operation(retriedRequest)
    }

    private func shouldAttemptAuthRefresh(
        for request: URLRequest,
        response: URLResponse
    ) -> Bool {
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 401 else {
            return false
        }

        guard request.value(forHTTPHeaderField: "Authorization")?.hasPrefix("Bearer ") == true else {
            return false
        }

        guard let path = request.url?.path else {
            return false
        }

        guard !path.hasPrefix("/api/v1/auth") else {
            return false
        }

        return authTokenStore.refreshToken?.nilIfBlank != nil
    }

    private func refreshAuthStateForRetry() async throws -> RefreshedAuthState {
        if let authRefreshTask {
            return try await authRefreshTask.value
        }

        let task = Task<RefreshedAuthState, Error> { @MainActor in
            guard let refreshToken = self.authTokenStore.refreshToken?.nilIfBlank else {
                throw APIClientError.requestFailed("登录态已失效，请重新登录")
            }

            let response = try await self.refreshAuthSession(refreshToken: refreshToken)
            guard let sessionToken = response.session.token?.nilIfBlank else {
                throw APIClientError.requestFailed("登录态已失效，请重新登录")
            }

            self.authTokenStore.sessionToken = sessionToken
            self.authTokenStore.refreshToken = response.session.refreshToken?.nilIfBlank ?? refreshToken
            return RefreshedAuthState(
                sessionToken: sessionToken,
                refreshToken: self.authTokenStore.refreshToken?.nilIfBlank
            )
        }

        authRefreshTask = task
        defer { authRefreshTask = nil }
        return try await task.value
    }

    private func requestByUpdatingAuthorization(
        for request: URLRequest,
        sessionToken: String
    ) -> URLRequest {
        var updatedRequest = request
        updatedRequest.setValue(Self.makeRequestID(), forHTTPHeaderField: Self.requestIDHeader)
        updatedRequest.setValue("Bearer \(sessionToken)", forHTTPHeaderField: "Authorization")
        return updatedRequest
    }

    private func performRetryableAIDataRequest(
        request: URLRequest
    ) async throws -> (Data, URLResponse) {
        for attempt in 0 ... Self.aiRequestRetryCount {
            do {
                let (data, response) = try await performDataRequest(request)
                if let httpResponse = response as? HTTPURLResponse,
                   Self.isRetryableAIStatusCode(httpResponse.statusCode),
                   attempt < Self.aiRequestRetryCount {
                    try await Self.sleepBeforeAIRetry(afterAttempt: attempt)
                    continue
                }

                return (data, response)
            } catch {
                if attempt < Self.aiRequestRetryCount, Self.isRetryableAITransportError(error) {
                    try await Self.sleepBeforeAIRetry(afterAttempt: attempt)
                    continue
                }

                throw error
            }
        }

        throw APIClientError.requestFailed("AI 请求失败，请稍后重试。")
    }

    private func makeRetryableAITextStream(
        request: URLRequest,
        fallback: String
    ) -> AsyncThrowingStream<String, Error> {
        let session = self.session

        return AsyncThrowingStream { continuation in
            let task = Task {
                for attempt in 0 ... Self.aiRequestRetryCount {
                    do {
                        let (bytes, response) = try await performRequestWithAuthRefresh(
                            request: request,
                            operation: { request in
                                try await session.bytes(for: request)
                            },
                            response: { result in result.1 }
                        )
                        guard let httpResponse = response as? HTTPURLResponse else {
                            throw APIClientError.invalidResponse
                        }

                        guard (200 ..< 300).contains(httpResponse.statusCode) else {
                            let detail = try await StreamTextReader.collect(from: bytes)
                            let message = Self.buildErrorMessage(
                                from: detail.isEmpty ? nil : Data(detail.utf8),
                                response: httpResponse,
                                fallback: fallback
                            )
                            if attempt < Self.aiRequestRetryCount,
                               Self.isRetryableAIStatusCode(httpResponse.statusCode) {
                                try await Self.sleepBeforeAIRetry(afterAttempt: attempt)
                                continue
                            }

                            throw APIClientError.requestFailed(message)
                        }

                        var receivedFirstChunk = false

                        do {
                            _ = try await StreamTextReader.consume(bytes: bytes) { accumulated in
                                receivedFirstChunk = true
                                continuation.yield(accumulated)
                            }
                            continuation.finish()
                            return
                        } catch {
                            if attempt < Self.aiRequestRetryCount,
                               !receivedFirstChunk,
                               Self.isRetryableAITransportError(error) {
                                try await Self.sleepBeforeAIRetry(afterAttempt: attempt)
                                continue
                            }

                            throw error
                        }
                    } catch {
                        if attempt < Self.aiRequestRetryCount, Self.isRetryableAITransportError(error) {
                            try await Self.sleepBeforeAIRetry(afterAttempt: attempt)
                            continue
                        }

                        continuation.finish(throwing: error)
                        return
                    }
                }

                continuation.finish(throwing: APIClientError.requestFailed(fallback))
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    private func validate(
        response: URLResponse,
        data: Data?,
        fallback: String = "请求失败，请检查后端日志。"
    ) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIClientError.invalidResponse
        }

        guard (200 ..< 300).contains(httpResponse.statusCode) else {
            let message = try parseErrorMessage(
                from: data,
                response: httpResponse,
                fallback: fallback
            )
            throw APIClientError.requestFailed(message)
        }
    }

    static func buildErrorMessage(
        from data: Data?,
        response: HTTPURLResponse? = nil,
        fallback: String = "请求失败，请检查后端日志。"
    ) -> String {
        let payload = data.flatMap { try? makeJSONDecoder().decode(APIErrorPayload.self, from: $0) }
        let requestID = payload?.requestId?.nilIfBlank ?? response?.value(forHTTPHeaderField: requestIDHeader)

        if let error = payload?.error?.nilIfBlank
            ?? payload?.errorDetail?.message?.nilIfBlank
            ?? payload?.message?.nilIfBlank {
            return appendRequestID(requestID, to: error)
        }

        if let text = data.flatMap({ String(data: $0, encoding: .utf8) })?.trimmingCharacters(in: .whitespacesAndNewlines),
           !text.isEmpty,
           !text.hasPrefix("<!DOCTYPE"),
           !text.hasPrefix("<html") {
            return appendRequestID(requestID, to: text)
        }

        return appendRequestID(requestID, to: formattedFallbackMessage(fallback, response: response))
    }

    private func parseErrorMessage(
        from data: Data?,
        response: HTTPURLResponse?,
        fallback: String
    ) throws -> String {
        Self.buildErrorMessage(from: data, response: response, fallback: fallback)
    }

    private static func appendRequestID(_ requestID: String?, to message: String) -> String {
        guard let requestID = requestID?.nilIfBlank else {
            return message
        }

        if message.contains(requestID) {
            return message
        }

        return "\(message) [RID: \(requestID)]"
    }

    private static func formattedFallbackMessage(
        _ fallback: String,
        response: HTTPURLResponse?
    ) -> String {
        guard let response else {
            return fallback
        }

        let normalizedFallback = fallback
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "。.!"))
        return "\(normalizedFallback)（HTTP \(response.statusCode)）"
    }

    private static func jwtExpirationDate(from token: String) -> Date? {
        let segments = token.split(separator: ".")
        guard segments.count >= 2 else {
            return nil
        }

        var payload = String(segments[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")

        let remainder = payload.count % 4
        if remainder != 0 {
            payload += String(repeating: "=", count: 4 - remainder)
        }

        guard let data = Data(base64Encoded: payload),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let exp = json["exp"] as? TimeInterval else {
            return nil
        }

        return Date(timeIntervalSince1970: exp)
    }

    private static func makeRequestID() -> String {
        UUID().uuidString.lowercased()
    }

    private static func isRetryableAITransportError(_ error: Error) -> Bool {
        guard let urlError = error as? URLError else {
            return false
        }

        switch urlError.code {
        case .timedOut, .networkConnectionLost, .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed:
            return true
        default:
            return false
        }
    }

    private static func isRetryableAIStatusCode(_ statusCode: Int) -> Bool {
        [429, 502, 503, 504].contains(statusCode)
    }

    private static func sleepBeforeAIRetry(afterAttempt attempt: Int) async throws {
        let delayNanoseconds = UInt64((attempt + 1) * 300_000_000)
        try await Task.sleep(nanoseconds: delayNanoseconds)
    }

    private nonisolated(unsafe) static let iso8601: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private nonisolated(unsafe) static let iso8601WithFractionalSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    nonisolated static func makeJSONDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()

            if let string = try? container.decode(String.self),
               let date = Self.iso8601WithFractionalSeconds.date(from: string) ?? Self.iso8601.date(from: string) {
                return date
            }

            if let milliseconds = try? container.decode(Double.self) {
                let normalizedSeconds = milliseconds > 10_000_000_000 ? (milliseconds / 1000) : milliseconds
                return Date(timeIntervalSince1970: normalizedSeconds)
            }

            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported date payload"
            )
        }
        return decoder
    }

    private static func makeMultipartBody(
        boundary: String,
        fileFieldName: String,
        fileName: String,
        mimeType: String,
        fileData: Data,
        textFields: [String: String]
    ) throws -> Data {
        var body = Data()
        let boundaryPrefix = "--\(boundary)\r\n"

        for (name, value) in textFields {
            body.append(Data(boundaryPrefix.utf8))
            body.append(Data("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".utf8))
            body.append(Data(value.utf8))
            body.append(Data("\r\n".utf8))
        }

        body.append(Data(boundaryPrefix.utf8))
        body.append(
            Data(
                "Content-Disposition: form-data; name=\"\(fileFieldName)\"; filename=\"\(fileName)\"\r\n".utf8
            )
        )
        body.append(Data("Content-Type: \(mimeType)\r\n\r\n".utf8))
        body.append(fileData)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        return body
    }
}

private struct EmptyAPIResponse: Decodable {}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
