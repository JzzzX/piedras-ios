import Foundation

private struct APIErrorPayload: Decodable {
    let error: String?
    let requestId: String?
    let route: String?
}

private struct MeetingTitleRequestPayload: Encodable {
    let transcript: String
    let durationSeconds: Int
    let meetingDate: String
}

private struct AuthLoginRequestPayload: Encodable {
    let email: String
    let password: String
}

private struct AuthRegisterRequestPayload: Encodable {
    let email: String
    let password: String
    let displayName: String?
}

private struct AuthPasswordResetRequestPayload: Encodable {
    let email: String
}

private struct AuthEmailOTPRequestPayload: Encodable {
    let email: String
    let intent: String
}

private struct AuthEmailOTPVerifyRequestPayload: Encodable {
    let email: String
    let token: String
}

private struct AuthSetPasswordRequestPayload: Encodable {
    let password: String
}

private struct AuthResendVerificationRequestPayload: Encodable {
    let email: String
}

private struct AuthRefreshRequestPayload: Encodable {
    let refreshToken: String
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
    private let settingsStore: SettingsStore
    private let authTokenStore: any AuthTokenStoring
    private let session: URLSession
    private let encoder = JSONEncoder()
    private let decoder: JSONDecoder

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
        try await sendJSONRequest(path: "/healthz", method: "GET", responseType: RemoteBackendHealth.self)
    }

    func fetchBackendWarmup() async throws -> RemoteBackendHealth {
        try await sendJSONRequest(
            path: "/healthz",
            method: "GET",
            queryItems: [URLQueryItem(name: "mode", value: "basic")],
            responseType: RemoteBackendHealth.self
        )
    }

    func fetchASRStatus() async throws -> RemoteASRStatus {
        try await sendJSONRequest(path: "/api/asr/status", method: "GET", responseType: RemoteASRStatus.self)
    }

    func fetchLLMStatus() async throws -> RemoteLLMStatus {
        try await sendJSONRequest(path: "/api/llm/status", method: "GET", responseType: RemoteLLMStatus.self)
    }

    func login(email: String, password: String) async throws -> RemoteAuthResponse {
        try await sendJSONRequest(
            path: "/api/auth/login",
            method: "POST",
            body: AuthLoginRequestPayload(email: email, password: password)
        )
    }

    func register(
        email: String,
        password: String,
        displayName: String?
    ) async throws -> RemoteAuthResponse {
        try await sendJSONRequest(
            path: "/api/auth/register",
            method: "POST",
            includeAuthorization: false,
            body: AuthRegisterRequestPayload(
                email: email,
                password: password,
                displayName: displayName
            )
        )
    }

    func sendEmailOTP(email: String, intent: EmailOTPIntent) async throws {
        let _: EmptyAPIResponse = try await sendJSONRequest(
            path: "/api/auth/email-otp/send",
            method: "POST",
            includeAuthorization: false,
            body: AuthEmailOTPRequestPayload(
                email: email,
                intent: intent.rawValue
            )
        )
    }

    func loginWithEmailOTP(email: String, token: String) async throws -> RemoteAuthResponse {
        try await sendJSONRequest(
            path: "/api/auth/email-otp/login",
            method: "POST",
            includeAuthorization: false,
            body: AuthEmailOTPVerifyRequestPayload(email: email, token: token)
        )
    }

    func registerWithEmailOTP(email: String, token: String) async throws -> RemoteAuthResponse {
        try await sendJSONRequest(
            path: "/api/auth/email-otp/register",
            method: "POST",
            includeAuthorization: false,
            body: AuthEmailOTPVerifyRequestPayload(email: email, token: token)
        )
    }

    func setPassword(password: String) async throws {
        let _: EmptyAPIResponse = try await sendJSONRequest(
            path: "/api/auth/password/set",
            method: "POST",
            body: AuthSetPasswordRequestPayload(password: password)
        )
    }

    func refreshAuthSession(refreshToken: String) async throws -> RemoteAuthResponse {
        try await sendJSONRequest(
            path: "/api/auth/refresh",
            method: "POST",
            includeAuthorization: false,
            body: AuthRefreshRequestPayload(refreshToken: refreshToken)
        )
    }

    func fetchAuthSession() async throws -> RemoteAuthSessionState {
        try await sendJSONRequest(
            path: "/api/auth/session",
            method: "GET",
            responseType: RemoteAuthSessionState.self
        )
    }

    func logout() async throws {
        let request = try makeRequest(path: "/api/auth/logout", method: "POST")
        let (data, response) = try await session.data(for: request)
        try validate(response: response, data: data, fallback: "退出登录失败。")
    }

    func requestPasswordReset(email: String) async throws {
        let _: EmptyAPIResponse = try await sendJSONRequest(
            path: "/api/auth/password-reset",
            method: "POST",
            includeAuthorization: false,
            body: AuthPasswordResetRequestPayload(email: email)
        )
    }

    func resendVerificationEmail(email: String) async throws {
        let _: EmptyAPIResponse = try await sendJSONRequest(
            path: "/api/auth/resend-verification",
            method: "POST",
            includeAuthorization: false,
            body: AuthResendVerificationRequestPayload(email: email)
        )
    }

    func createASRSession(
        sampleRate: Int,
        channels: Int,
        workspaceID: String?
    ) async throws -> RemoteASRSessionResponse {
        try await sendJSONRequest(
            path: "/api/asr/session",
            method: "POST",
            body: ASRSessionRequestPayload(
                sampleRate: sampleRate,
                channels: channels,
                workspaceId: workspaceID
            )
        )
    }

    func listWorkspaces() async throws -> [RemoteWorkspace] {
        try await sendJSONRequest(path: "/api/workspaces", method: "GET", responseType: [RemoteWorkspace].self)
    }

    func createWorkspace(_ payload: WorkspaceCreatePayload) async throws -> RemoteWorkspace {
        try await sendJSONRequest(path: "/api/workspaces", method: "POST", body: payload)
    }

    func listMeetings(workspaceID: String) async throws -> [RemoteMeetingListItem] {
        try await sendJSONRequest(
            path: "/api/meetings",
            method: "GET",
            queryItems: [URLQueryItem(name: "workspaceId", value: workspaceID)],
            responseType: [RemoteMeetingListItem].self
        )
    }

    func getMeeting(id: String) async throws -> RemoteMeetingDetail {
        try await sendJSONRequest(path: "/api/meetings/\(id)", method: "GET", responseType: RemoteMeetingDetail.self)
    }

    func upsertMeeting(_ payload: MeetingUpsertPayload) async throws -> RemoteMeetingDetail {
        try await sendJSONRequest(path: "/api/meetings", method: "POST", body: payload)
    }

    func deleteMeeting(id: String) async throws {
        let request = try makeRequest(path: "/api/meetings/\(id)", method: "DELETE")
        let (data, response) = try await session.data(for: request)
        try validate(response: response, data: data, fallback: "删除会议失败。")
    }

    func uploadAudio(
        meetingID: String,
        fileURL: URL,
        duration: Int,
        mimeType: String
    ) async throws -> RemoteAudioUploadResponse {
        guard let fileData = try? Data(contentsOf: fileURL) else {
            throw APIClientError.unreadableFile
        }

        let boundary = "Boundary-\(UUID().uuidString.lowercased())"
        var request = try makeRequest(path: "/api/meetings/\(meetingID)/audio", method: "POST")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = makeMultipartBody(
            boundary: boundary,
            fileData: fileData,
            filename: fileURL.lastPathComponent,
            duration: duration,
            mimeType: mimeType
        )

        let (data, response) = try await session.data(for: request)
        try validate(response: response, data: data)
        return try decoder.decode(RemoteAudioUploadResponse.self, from: data)
    }

    func uploadAudioAndFinalizeTranscript(
        meetingID: String,
        fileURL: URL,
        duration: Int,
        mimeType: String
    ) async throws -> RemoteMeetingDetail {
        guard let fileData = try? Data(contentsOf: fileURL) else {
            throw APIClientError.unreadableFile
        }

        let boundary = "Boundary-\(UUID().uuidString.lowercased())"
        var request = try makeRequest(
            path: "/api/meetings/\(meetingID)/audio",
            method: "POST",
            queryItems: [URLQueryItem(name: "finalizeTranscript", value: "true")]
        )
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = makeMultipartBody(
            boundary: boundary,
            fileData: fileData,
            filename: fileURL.lastPathComponent,
            duration: duration,
            mimeType: mimeType
        )

        let (data, response) = try await session.data(for: request)
        try validate(response: response, data: data)
        return try decoder.decode(RemoteMeetingDetail.self, from: data)
    }

    func enhanceNotes(_ payload: EnhanceRequestPayload) async throws -> RemoteEnhanceResponse {
        try await sendJSONRequest(path: "/api/enhance", method: "POST", body: payload)
    }

    func generateMeetingTitle(
        transcript: String,
        durationSeconds: Int,
        meetingDate: Date
    ) async throws -> RemoteMeetingTitleResponse {
        try await sendJSONRequest(
            path: "/api/meetings/title",
            method: "POST",
            body: MeetingTitleRequestPayload(
                transcript: transcript,
                durationSeconds: durationSeconds,
                meetingDate: Self.iso8601WithFractionalSeconds.string(from: meetingDate)
            )
        )
    }

    func streamChat(_ payload: ChatRequestPayload) async throws -> AsyncThrowingStream<String, Error> {
        var request = try makeRequest(path: "/api/chat", method: "POST")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(payload)

        let (bytes, response) = try await session.bytes(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIClientError.invalidResponse
        }

        guard (200 ..< 300).contains(httpResponse.statusCode) else {
            let detail = try await StreamTextReader.collect(from: bytes)
            let message = Self.buildErrorMessage(
                from: detail.isEmpty ? nil : Data(detail.utf8),
                response: httpResponse,
                fallback: "会议对话请求失败。"
            )
            throw APIClientError.requestFailed(message)
        }

        return StreamTextReader.stream(from: bytes)
    }

    func streamGlobalChat(_ payload: GlobalChatRequestPayload) async throws -> AsyncThrowingStream<String, Error> {
        var request = try makeRequest(path: "/api/chat/global", method: "POST")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(payload)

        let (bytes, response) = try await session.bytes(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIClientError.invalidResponse
        }

        guard (200 ..< 300).contains(httpResponse.statusCode) else {
            let detail = try await StreamTextReader.collect(from: bytes)
            let message = Self.buildErrorMessage(
                from: detail.isEmpty ? nil : Data(detail.utf8),
                response: httpResponse,
                fallback: "全局 AI 请求失败。"
            )
            throw APIClientError.requestFailed(message)
        }

        return StreamTextReader.stream(from: bytes)
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
        responseType: Response.Type
    ) async throws -> Response {
        let request = try makeRequest(
            path: path,
            method: method,
            queryItems: queryItems,
            includeAuthorization: includeAuthorization
        )
        let (data, response) = try await session.data(for: request)
        try validate(response: response, data: data)
        return try decoder.decode(responseType, from: data)
    }

    private func sendJSONRequest<Response: Decodable, Body: Encodable>(
        path: String,
        method: String,
        queryItems: [URLQueryItem] = [],
        includeAuthorization: Bool = true,
        body: Body
    ) async throws -> Response {
        var request = try makeRequest(
            path: path,
            method: method,
            queryItems: queryItems,
            includeAuthorization: includeAuthorization
        )
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(body)

        let (data, response) = try await session.data(for: request)
        try validate(response: response, data: data)
        return try decoder.decode(Response.self, from: data)
    }

    private func makeRequest(
        path: String,
        method: String,
        queryItems: [URLQueryItem] = [],
        includeAuthorization: Bool = true
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
        request.timeoutInterval = 30
        if includeAuthorization,
           let sessionToken = authTokenStore.sessionToken?.nilIfBlank {
            request.setValue("Bearer \(sessionToken)", forHTTPHeaderField: "Authorization")
        }
        return request
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

        if let error = payload?.error?.nilIfBlank {
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

    private func makeMultipartBody(
        boundary: String,
        fileData: Data,
        filename: String,
        duration: Int,
        mimeType: String
    ) -> Data {
        var body = Data()
        let lineBreak = "\r\n"

        body.append("--\(boundary)\(lineBreak)".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"duration\"\(lineBreak)\(lineBreak)".data(using: .utf8)!)
        body.append("\(duration)\(lineBreak)".data(using: .utf8)!)

        body.append("--\(boundary)\(lineBreak)".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"mimeType\"\(lineBreak)\(lineBreak)".data(using: .utf8)!)
        body.append("\(mimeType)\(lineBreak)".data(using: .utf8)!)

        body.append("--\(boundary)\(lineBreak)".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\(lineBreak)".data(using: .utf8)!)
        body.append("Content-Type: \(mimeType)\(lineBreak)\(lineBreak)".data(using: .utf8)!)
        body.append(fileData)
        body.append(lineBreak.data(using: .utf8)!)

        body.append("--\(boundary)--\(lineBreak)".data(using: .utf8)!)
        return body
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
}

private struct EmptyAPIResponse: Decodable {}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
