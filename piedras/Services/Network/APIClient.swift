import Foundation

private struct APIErrorPayload: Decodable {
    let error: String?
}

enum APIClientError: LocalizedError {
    case missingBaseURL
    case invalidResponse
    case requestFailed(String)
    case unreadableFile

    var errorDescription: String? {
        switch self {
        case .missingBaseURL:
            return "请先在设置中填写可访问的后端地址。"
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
final class APIClient {
    private let settingsStore: SettingsStore
    private let session: URLSession
    private let encoder = JSONEncoder()
    private let decoder: JSONDecoder

    init(settingsStore: SettingsStore, session: URLSession = .shared) {
        self.settingsStore = settingsStore
        self.session = session

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            if let date = Self.iso8601WithFractionalSeconds.date(from: string) ?? Self.iso8601.date(from: string) {
                return date
            }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid ISO8601 date string: \(string)"
            )
        }
        self.decoder = decoder
    }

    var baseURL: URL? {
        settingsStore.backendBaseURL
    }

    func fetchASRStatus() async throws -> RemoteASRStatus {
        try await sendJSONRequest(path: "/api/asr/status", method: "GET", responseType: RemoteASRStatus.self)
    }

    func fetchLLMStatus() async throws -> RemoteLLMStatus {
        try await sendJSONRequest(path: "/api/llm/status", method: "GET", responseType: RemoteLLMStatus.self)
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
        let (_, response) = try await session.data(for: request)
        try validate(response: response, data: nil)
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

    func enhanceNotes(_ payload: EnhanceRequestPayload) async throws -> RemoteEnhanceResponse {
        try await sendJSONRequest(path: "/api/enhance", method: "POST", body: payload)
    }

    func generateMeetingTitle(transcript: String) async throws -> RemoteMeetingTitleResponse {
        try await sendJSONRequest(
            path: "/api/meetings/title",
            method: "POST",
            body: ["transcript": transcript]
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
            throw APIClientError.requestFailed(detail.isEmpty ? "会议对话请求失败。" : detail)
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
            throw APIClientError.requestFailed(detail.isEmpty ? "全局 AI 请求失败。" : detail)
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
        responseType: Response.Type
    ) async throws -> Response {
        let request = try makeRequest(path: path, method: method, queryItems: queryItems)
        let (data, response) = try await session.data(for: request)
        try validate(response: response, data: data)
        return try decoder.decode(responseType, from: data)
    }

    private func sendJSONRequest<Response: Decodable, Body: Encodable>(
        path: String,
        method: String,
        queryItems: [URLQueryItem] = [],
        body: Body
    ) async throws -> Response {
        var request = try makeRequest(path: path, method: method, queryItems: queryItems)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(body)

        let (data, response) = try await session.data(for: request)
        try validate(response: response, data: data)
        return try decoder.decode(Response.self, from: data)
    }

    private func makeRequest(
        path: String,
        method: String,
        queryItems: [URLQueryItem] = []
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
        return request
    }

    private func validate(response: URLResponse, data: Data?) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIClientError.invalidResponse
        }

        guard (200 ..< 300).contains(httpResponse.statusCode) else {
            let message = try parseErrorMessage(from: data)
            throw APIClientError.requestFailed(message)
        }
    }

    private func parseErrorMessage(from data: Data?) throws -> String {
        guard let data, !data.isEmpty else {
            return "请求失败，请检查后端日志。"
        }

        if let payload = try? decoder.decode(APIErrorPayload.self, from: data),
           let error = payload.error,
           !error.isEmpty {
            return error
        }

        if let text = String(data: data, encoding: .utf8), !text.isEmpty {
            return text
        }

        return "请求失败，请检查后端日志。"
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
}
